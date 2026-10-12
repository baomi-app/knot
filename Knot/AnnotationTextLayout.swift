import AppKit

/// Shared text metrics for editing, hit testing, preview and image export.
struct AnnotationTextLayout {
    let attributedString: NSAttributedString
    let containerWidth: CGFloat
    let size: CGSize

    init(text: String, fontSize: CGFloat, color: NSColor, width: CGFloat) {
        let font = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byWordWrapping
        let string = NSAttributedString(string: text, attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: paragraph
        ])
        let storage = NSTextStorage(attributedString: string)
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: max(1, width), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)
        manager.ensureLayout(for: container)
        let used = manager.usedRect(for: container)
        let extraHeight = manager.extraLineFragmentTextContainer == container
            ? manager.extraLineFragmentRect.maxY : 0
        self.attributedString = string
        self.containerWidth = max(1, width)
        self.size = CGSize(
            width: max(1, ceil(used.width)),
            height: ceil(max(manager.defaultLineHeight(for: font), used.maxY, extraHeight))
        )
    }

    /// Coordinates are bottom-origin, while the text anchor is its top-left.
    func frame(at topLeft: CGPoint) -> CGRect {
        CGRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height)
    }

    func draw(at topLeft: CGPoint, scale: CGFloat = 1) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: topLeft.x, yBy: topLeft.y)
        transform.scale(by: scale)
        transform.concat()
        // Scale the rendered layout, not the font: system font metrics can change
        // with its point size, which would otherwise reflow Retina exports.
        let rect = CGRect(x: 0, y: -size.height, width: containerWidth, height: size.height)
        attributedString.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    }
}

/// Keeps the initial grab offset and clamps the whole text block to the capture.
struct AnnotationTextDrag {
    let id: UUID
    let start: CGPoint
    let mouseDown: CGPoint
    let textSize: CGSize

    func position(at point: CGPoint, in capture: CGRect) -> CGPoint {
        guard capture.width > 0, capture.height > 0 else { return start }
        let x = start.x * capture.width + point.x - mouseDown.x
        let y = start.y * capture.height - (point.y - mouseDown.y)
        return CGPoint(
            x: min(max(0, x), max(0, capture.width - textSize.width)) / capture.width,
            y: min(max(0, y), max(0, capture.height - textSize.height)) / capture.height
        )
    }
}
