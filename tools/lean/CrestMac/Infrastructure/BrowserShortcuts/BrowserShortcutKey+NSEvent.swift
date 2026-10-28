import AppKit

extension BrowserShortcutKey {
    init?(event: NSEvent) {
        if let specialKey = ShortcutSpecialKey(keyCode: event.keyCode) {
            self = .special(specialKey)
            return
        }
        guard
            let characters = event.charactersIgnoringModifiers?.lowercased(),
            characters.count == 1,
            let character = characters.first,
            !character.isNewline,
            !character.isWhitespace
        else {
            return nil
        }
        self = .character(character)
    }
}
