import AppKit
import Carbon.HIToolbox
import XCTest

@MainActor
final class AnnotationTextTests: XCTestCase {
    private var editorWindow: NSWindow?
    func testReturnAddsANewlineAndContinuesEditing() throws {
        let editor = makeEditor()
        var commits = 0
        editor.onCommit = { commits += 1 }
        editor.insertText("第一行", replacementRange: NSRange(location: NSNotFound, length: 0))
        editor.keyDown(with: try key(kVK_Return, characters: "\r"))
        editor.insertText("第二行", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(editor.string, "第一行\n第二行")
        XCTAssertEqual(commits, 0)
        XCTAssertGreaterThan(layout(editor.string).size.height, layout("第一行").size.height)
    }

    func testCommandReturnCommitsWithoutAddingANewline() throws {
        let editor = makeEditor(text: "First\nSecond")
        var commits = 0
        editor.onCommit = { commits += 1 }
        editor.keyDown(with: try key(kVK_Return, characters: "\r", flags: .command))

        XCTAssertEqual(editor.string, "First\nSecond")
        XCTAssertEqual(commits, 1)
    }

    func testEscapeCancelsTheEditor() throws {
        let editor = makeEditor(text: "Existing text")
        var cancels = 0
        editor.onCancel = { cancels += 1 }
        editor.keyDown(with: try key(kVK_Escape, characters: "\u{1b}"))

        XCTAssertEqual(cancels, 1)
        XCTAssertEqual(editor.string, "Existing text")
    }

    func testMarkedChineseTextIsNotCommittedAsAnAnnotation() throws {
        let editor = makeEditor()
        var commits = 0
        editor.onCommit = { commits += 1 }
        editor.setMarkedText("拼音", selectedRange: NSRange(location: 2, length: 0),
                             replacementRange: NSRange(location: NSNotFound, length: 0))
        XCTAssertTrue(editor.hasMarkedText())
        editor.keyDown(with: try key(kVK_Return, characters: "\r", flags: .command))
        XCTAssertEqual(commits, 0)
    }

    func testTrailingNewlinesKeepSpaceForTheInsertionPoint() {
        let one = layout("Line")
        let two = layout("Line\n")
        let three = layout("Line\n\n")
        XCTAssertGreaterThan(layout("").size.height, 0)
        XCTAssertGreaterThan(two.size.height, one.size.height)
        XCTAssertGreaterThan(three.size.height, two.size.height)
    }

    func testLongTextWrapsWithinTheStoredWidth() {
        let text = "文字可以换行，也可以自动折行。Text can wrap within its annotation.\nSecond paragraph."
        let narrow = layout(text, width: 120)
        let wide = layout(text, width: 500)
        XCTAssertGreaterThan(narrow.size.height, wide.size.height)
        XCTAssertLessThanOrEqual(narrow.size.width, 120)
        let rect = narrow.frame(at: CGPoint(x: 50, y: 300))
        XCTAssertEqual(rect.maxY, 300)
        XCTAssertEqual(rect.minX, 50)
    }

    func testExportDrawsBothLinesAtStandardAndRetinaScales() throws {
        var inkBounds: [CGRect] = []
        for scale: CGFloat in [1, 2] {
            let width = Int(320 * scale), height = Int(180 * scale)
            let rep = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            rep.size = CGSize(width: width, height: height)
            let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: rep))
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            NSColor.white.setFill()
            CGRect(x: 0, y: 0, width: width, height: height).fill()
            AnnotationTextLayout(text: "First\nSecond", fontSize: 22,
                                 color: .black, width: 260)
                .draw(at: CGPoint(x: 30 * scale, y: 150 * scale), scale: scale)
            context.flushGraphics()
            NSGraphicsContext.restoreGraphicsState()

            var bands = 0
            var previousRowHadInk = false
            var bounds = CGRect.null
            for y in 0..<height {
                var hasInk = false
                for x in 0..<width {
                    if let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.redComponent < 0.5 {
                        hasInk = true
                        bounds = bounds.union(CGRect(x: x, y: y, width: 1, height: 1))
                    }
                }
                if hasInk && !previousRowHadInk { bands += 1 }
                previousRowHadInk = hasInk
            }
            XCTAssertEqual(bands, 2, "Both lines must be exported at scale \(scale)")
            inkBounds.append(bounds)
        }
        XCTAssertEqual(inkBounds[1].minX, inkBounds[0].minX * 2, accuracy: 2)
        XCTAssertEqual(inkBounds[1].minY, inkBounds[0].minY * 2, accuracy: 2)
        XCTAssertEqual(inkBounds[1].maxX, inkBounds[0].maxX * 2, accuracy: 2)
        XCTAssertEqual(inkBounds[1].maxY, inkBounds[0].maxY * 2, accuracy: 2)
    }

    func testTextDragPreservesGrabOffsetAndUsesTopOriginCoordinates() {
        let capture = CGRect(x: 100, y: 80, width: 400, height: 300)
        let drag = AnnotationTextDrag(id: UUID(), start: CGPoint(x: 0.2, y: 0.3),
                                      mouseDown: CGPoint(x: 200, y: 260), textSize: CGSize(width: 100, height: 60))
        XCTAssertEqual(drag.position(at: drag.mouseDown, in: capture), drag.start)
        let moved = drag.position(at: CGPoint(x: 280, y: 290), in: capture)
        XCTAssertEqual(moved.x, 0.4, accuracy: 0.0001)
        XCTAssertEqual(moved.y, 0.2, accuracy: 0.0001)
    }

    func testDraggingKeepsTheEntireMultilineBlockInsideTheCapture() {
        let drag = AnnotationTextDrag(id: UUID(), start: CGPoint(x: 0.2, y: 0.3),
                                      mouseDown: CGPoint(x: 200, y: 260), textSize: CGSize(width: 100, height: 60))
        let capture = CGRect(x: 100, y: 80, width: 400, height: 300)
        let bottomRight = drag.position(at: CGPoint(x: 2_000, y: -2_000), in: capture)
        XCTAssertEqual(bottomRight.x, 0.75)
        XCTAssertEqual(bottomRight.y, 0.8)
        XCTAssertEqual(drag.position(at: CGPoint(x: -2_000, y: 2_000), in: capture), .zero)
    }

    private func layout(_ text: String, width: CGFloat = 280) -> AnnotationTextLayout {
        AnnotationTextLayout(text: text, fontSize: 22, color: .red, width: width)
    }

    private func makeEditor(text: String = "") -> AnnotationTextView {
        let frame = CGRect(x: 0, y: 0, width: 280, height: 100)
        let editor = AnnotationTextView(frame: frame, text: text, fontSize: 22, color: .red)
        let window = NSWindow(contentRect: frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor
        window.makeFirstResponder(editor)
        editorWindow = window
        return editor
    }

    private func key(_ code: Int, characters: String, flags: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                      timestamp: 0, windowNumber: editorWindow?.windowNumber ?? 0, context: nil,
                                      characters: characters, charactersIgnoringModifiers: characters,
                                      isARepeat: false, keyCode: UInt16(code)))
    }
}
