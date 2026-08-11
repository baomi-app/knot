import AppKit
import Foundation
import Vision

enum CaptureAction: String, Codable, CaseIterable, Hashable, Sendable {
    case smartCapture = "Capture & Annotate"
    case areaToFile = "Capture Area"
    case windowToFile = "Capture Window"
    case fullScreenToFile = "Capture Full Screen"
    case areaToClipboard = "Capture Area to Clipboard"
    case areaAndOCR = "Capture Area and Extract Text"

    static let availableActions: [CaptureAction] = [.smartCapture, .areaAndOCR]

    var subtitle: String {
        switch self {
        case .smartCapture: "Hover for a window, drag for an area, or press Return for full screen"
        case .areaToFile: "Select an area and save it using Capture settings"
        case .windowToFile: "Select a window and save it"
        case .fullScreenToFile: "Save the main display using Capture settings"
        case .areaToClipboard: "Copy a selected area as an image"
        case .areaAndOCR: "Recognize text locally and copy it"
        }
    }

    var symbol: String {
        switch self {
        case .smartCapture: "viewfinder.circle"
        case .areaToFile: "viewfinder"
        case .windowToFile: "macwindow"
        case .fullScreenToFile: "rectangle.inset.filled"
        case .areaToClipboard: "photo.on.rectangle"
        case .areaAndOCR: "text.viewfinder"
        }
    }
}

enum CaptureResult: Equatable, Sendable {
    case started
    case saved(URL)
    case annotationOpened(URL)
    case copiedImage
    case copiedText(Int)
    case cancelled
    case noText
    case failed

    var message: String {
        switch self {
        case .started: "Capture started"
        case .saved(let url): "Saved to \(url.lastPathComponent)"
        case .annotationOpened(let url): "Saved and opened \(url.lastPathComponent) for annotation"
        case .copiedImage: "Screenshot copied to clipboard"
        case .copiedText(let count): "Copied \(count) recognized characters"
        case .cancelled: "Capture cancelled"
        case .noText: "No text was found in the capture"
        case .failed: "Capture could not be completed"
        }
    }
}

@MainActor
enum CaptureManager {
    static func perform(_ action: CaptureAction) async -> CaptureResult {
        try? await Task.sleep(for: .milliseconds(180))

        switch action {
        case .smartCapture, .areaToFile, .windowToFile, .fullScreenToFile, .areaToClipboard:
            CaptureCoordinator.shared.unified()
            return .started

        case .areaAndOCR:
            let temporaryURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("Knot-OCR-\(UUID().uuidString).png")
            defer { try? FileManager.default.removeItem(at: temporaryURL) }

            let status = await runScreenCapture(arguments: ["-i", "-s", temporaryURL.path])
            guard status == 0,
                  FileManager.default.fileExists(atPath: temporaryURL.path) else {
                return status == 1 ? .cancelled : .failed
            }

            guard let text = try? await recognizeText(at: temporaryURL), !text.isEmpty else {
                return .noText
            }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return .copiedText(text.count)
        }
    }

    private static func runScreenCapture(arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            process.arguments = arguments
            process.terminationHandler = { process in
                continuation.resume(returning: process.terminationStatus)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: -1)
            }
        }
    }

    private static func recognizeText(at url: URL) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]

            let handler = VNImageRequestHandler(url: url)
            try handler.perform([request])
            return (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.value
    }

}
