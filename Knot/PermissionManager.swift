import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
enum PermissionManager {
    static var accessibilityGranted: Bool { AXIsProcessTrusted() }
    static var screenRecordingGranted: Bool { CGPreflightScreenCaptureAccess() }

    @discardableResult
    static func requestAccessibility() -> Bool {
        AXIsProcessTrustedWithOptions(
            ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        )
    }

    @discardableResult
    static func requestScreenRecording() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openAccessibilitySettings() {
        openSettings(anchor: "Privacy_Accessibility")
    }

    static func openScreenRecordingSettings() {
        openSettings(anchor: "Privacy_ScreenCapture")
    }

    private static func openSettings(anchor: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") else { return }
        NSWorkspace.shared.open(url)
    }
}
