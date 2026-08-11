import AppKit
import ScreenCaptureKit
import CoreGraphics

/// Capture flow orchestration.
/// The selection overlay freezes the screen and crops the requested area from that
/// frozen snapshot, so an intent already carries the finished image.
/// - Region / window (.region): open the in-place annotation overlay at its original spot.
/// - Full screen (.direct): copy to clipboard + save + "pop" feedback.
@MainActor
final class CaptureCoordinator {
    static let shared = CaptureCoordinator()

    /// Unified capture mode: drag = region, click = window, Return = full screen, Esc = cancel.
    func unified() {
        // Verify Screen Recording permission first; otherwise the overlay is useless.
        guard CGPreflightScreenCaptureAccess() else {
            Toast.show(String(localized: "需要屏幕录制权限。授权后退出 Knot 再打开。"))
            // Trigger the system prompt (first time); otherwise open System Settings directly.
            if !CGRequestScreenCaptureAccess() {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                    NSWorkspace.shared.open(url)
                }
            }
            return
        }

        RegionSelectionController.shared.begin { intent, screen in
            switch intent {
            case .cancel:
                return
            case .direct(let image):
                // Full screen: finalize directly (no in-place editing).
                CaptureCoordinator.finalize(image)
            case .region(let image, let rectGlobal):
                // Region / window: open the in-place annotation overlay at its original spot.
                // The selection overlay stays up (dimmed) underneath until editing ends.
                let fullScreen = RegionSelectionController.shared.snapshot(for: screen)
                AnnotationOverlayController.shared.present(
                    base: image, rectGlobal: rectGlobal, screen: screen, fullScreen: fullScreen)
            }
        }
    }

    // MARK: -

    /// Copy to clipboard + (optionally) save to disk + (optionally) "pop" feedback.
    static func finalize(_ cgImage: CGImage) {
        ClipboardService.copy(cgImage)

        let store = HotkeyStore.shared
        if store.saveEnabled, store.savePath != nil {
            do {
                _ = try store.withSaveDirectoryAccess { dir in
                    try ImageSaver.savePNG(cgImage, to: dir)
                }
            } catch {
                NSLog("[Knot Capture] Save to disk failed: \(error)")
            }
        }

        if store.toastEnabled {
            Toast.show(Brand.Copy.saved)
        }
    }
}
