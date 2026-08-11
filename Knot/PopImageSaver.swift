import AppKit
import CoreGraphics

@MainActor
enum ImageSaver {
    @discardableResult
    static func savePNG(_ cgImage: CGImage, to dir: URL) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let settings = CaptureSettingsStore.shared
        let url = dir.appendingPathComponent(
            "\(settings.fileNamePrefix)-\(timestamp()).\(settings.format.fileExtension)"
        )
        let rep = NSBitmapImageRep(cgImage: cgImage)
        let data = settings.format == .png
            ? rep.representation(using: .png, properties: [:])
            : rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])
        guard let data else {
            throw CaptureError.encodeFailed
        }
        try data.write(to: url)
        CaptureHistoryStore.shared.record(fileURL: url, action: .smartCapture)
        return url
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return f.string(from: Date())
    }
}
