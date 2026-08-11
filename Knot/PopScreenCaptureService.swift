import ScreenCaptureKit
import CoreGraphics
import AppKit

enum CaptureError: Error {
    case noDisplay
    case encodeFailed
}

/// Still-image screenshot service built on ScreenCaptureKit (macOS 14+).
enum ScreenCaptureService {

    static func shareableContent() async throws -> SCShareableContent {
        try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    }

    // MARK: - Full screen

    /// Capture a full screen by NSScreen.
    static func captureFullScreen(of screen: NSScreen) async throws -> CGImage {
        let content = try await shareableContent()
        let display = content.displays.first { $0.displayID == screen.displayID }
            ?? content.displays.first
        guard let display else { throw CaptureError.noDisplay }
        return try await capture(display: display, cropRect: nil, scale: scale(for: display))
    }

    // MARK: - Region

    /// cropRect: a point rect in the display's coordinate space, origin at top-left.
    /// `excluding`: windows to leave out of the capture (e.g. our own dimming overlay,
    /// so the selection layer can stay up during capture without a flash).
    static func captureRegion(_ cropRect: CGRect, on display: SCDisplay,
                              excluding: [SCWindow] = []) async throws -> CGImage {
        try await capture(display: display, cropRect: cropRect,
                          scale: scale(for: display), excluding: excluding)
    }

    // MARK: - Window

    /// Capture a specific SCWindow.
    static func capture(_ window: SCWindow) async throws -> CGImage {
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        let s = NSScreen.main?.backingScaleFactor ?? 2.0
        config.width = Int(window.frame.width * s)
        config.height = Int(window.frame.height * s)
        config.showsCursor = false
        config.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    // MARK: - Core

    private static func capture(display: SCDisplay, cropRect: CGRect?, scale: CGFloat,
                                excluding: [SCWindow] = []) async throws -> CGImage {
        let filter = SCContentFilter(display: display, excludingWindows: excluding)
        let config = SCStreamConfiguration()
        config.width = Int(CGFloat(display.width) * scale)
        config.height = Int(CGFloat(display.height) * scale)
        config.showsCursor = false
        config.captureResolution = .best

        let full = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let cropRect else { return full }

        let px = CGRect(
            x: cropRect.origin.x * scale,
            y: cropRect.origin.y * scale,
            width: cropRect.width * scale,
            height: cropRect.height * scale
        )
        return full.cropping(to: px) ?? full
    }

    // MARK: - Helpers

    static func scale(for display: SCDisplay) -> CGFloat {
        NSScreen.screens.first { $0.displayID == display.displayID }?.backingScaleFactor ?? 2.0
    }

    /// Convert a rect in global screen coordinates (bottom-left origin) into a
    /// point rect local to the display, with a top-left origin.
    static func topLeftRect(_ rect: CGRect, in screen: NSScreen) -> CGRect {
        let f = screen.frame
        return CGRect(
            x: rect.minX - f.minX,
            y: f.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID) ?? 0
    }
}
