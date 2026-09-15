import AppKit
import CoreGraphics

@MainActor
enum ClipboardService {
    static func copy(_ cgImage: CGImage) {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        guard pb.setData(data, forType: .png) else { return }
        ClipboardMonitor.shared.recordCurrentImage(sourceName: "Knot Capture")
    }

    @discardableResult
    static func copyText(
        _ text: String,
        to pb: NSPasteboard = .general,
        monitor: ClipboardMonitor? = nil
    ) -> Bool {
        pb.clearContents()
        guard pb.setString(text, forType: .string) else { return false }
        (monitor ?? ClipboardMonitor.shared).recordCurrentText(sourceName: "Knot OCR")
        return true
    }
}
