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

    static func copyText(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}
