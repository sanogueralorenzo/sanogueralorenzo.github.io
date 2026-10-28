import SwiftUI

extension BrowserShortcut {
    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(
            key.keyEquivalent,
            modifiers: modifiers.eventModifiers
        )
    }
}
