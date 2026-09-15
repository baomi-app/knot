import AppKit

enum CommandPanelKeyCommand: Equatable {
    case showSettings
    case acceptSuggestion

    static func resolve(_ event: NSEvent) -> Self? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        if event.charactersIgnoringModifiers == ",", modifiers == .command {
            return .showSettings
        }
        if event.keyCode == 48, modifiers.isEmpty {
            return .acceptSuggestion
        }
        return nil
    }
}
