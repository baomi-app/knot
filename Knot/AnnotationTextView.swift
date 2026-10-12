import AppKit
import Carbon.HIToolbox

/// A plain multiline editor; Return stays in the text system, including IME input.
final class AnnotationTextView: NSTextView, NSTextViewDelegate {
    private let annotationStorage = NSTextStorage()
    var onChange: (() -> Void)?
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    init(frame: CGRect, text: String, fontSize: CGFloat, color: NSColor) {
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: frame.width, height: .greatestFiniteMagnitude))
        annotationStorage.addLayoutManager(manager)
        manager.addTextContainer(container)
        super.init(frame: frame, textContainer: container)
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isHorizontallyResizable = false
        isVerticallyResizable = true
        minSize = .zero
        maxSize = NSSize(width: frame.width, height: .greatestFiniteMagnitude)
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        textContainer?.containerSize = NSSize(width: frame.width, height: .greatestFiniteMagnitude)
        let layout = AnnotationTextLayout(text: text, fontSize: fontSize, color: color, width: frame.width)
        textStorage?.setAttributedString(layout.attributedString)
        typingAttributes = AnnotationTextLayout(text: " ", fontSize: fontSize, color: color, width: frame.width)
            .attributedString.attributes(at: 0, effectiveRange: nil)
        font = .systemFont(ofSize: fontSize, weight: .semibold)
        textColor = color
        insertionPointColor = color
        backgroundColor = NSColor.black.withAlphaComponent(0.5)
        delegate = self
        setAccessibilityLabel(String(localized: "标注文字"))
        toolTip = String(localized: "回车换行，⌘↩ 完成，Esc 取消")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func keyDown(with event: NSEvent) {
        // Let an input method finish/cancel its marked text before handling
        // annotation commands, so Chinese composition is not committed early.
        if !hasMarkedText() {
            if [UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter)].contains(event.keyCode),
               event.modifierFlags.contains(.command) {
                onCommit?()
                return
            }
            if event.keyCode == UInt16(kVK_Escape) {
                onCancel?()
                return
            }
        }
        super.keyDown(with: event)
    }

    func textDidChange(_ notification: Notification) {
        onChange?()
    }
}
