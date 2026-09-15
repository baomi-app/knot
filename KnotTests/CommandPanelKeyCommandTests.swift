import AppKit
import XCTest

final class CommandPanelKeyCommandTests: XCTestCase {
    func testCommandCommaRoutesToSettings() throws {
        XCTAssertEqual(CommandPanelKeyCommand.resolve(try event(",", code: 43, flags: .command)), .showSettings)
        XCTAssertEqual(CommandPanelKeyCommand.resolve(try event(",", code: 43, flags: [.command, .capsLock])), .showSettings)
    }

    func testOtherCommaShortcutsAreNotConsumed() throws {
        for flags: NSEvent.ModifierFlags in [[], .option, [.command, .shift], [.command, .option]] {
            XCTAssertNil(CommandPanelKeyCommand.resolve(try event(",", code: 43, flags: flags)))
        }
    }

    func testOnlyUnmodifiedTabCompletesSuggestion() throws {
        XCTAssertEqual(CommandPanelKeyCommand.resolve(try event("\t", code: 48, flags: [])), .acceptSuggestion)
        XCTAssertNil(CommandPanelKeyCommand.resolve(try event("\t", code: 48, flags: .shift)))
        XCTAssertNil(CommandPanelKeyCommand.resolve(try event("\t", code: 48, flags: .command)))
    }

    private func event(_ characters: String, code: UInt16, flags: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
            windowNumber: 0, context: nil, characters: characters,
            charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code
        ))
    }
}
