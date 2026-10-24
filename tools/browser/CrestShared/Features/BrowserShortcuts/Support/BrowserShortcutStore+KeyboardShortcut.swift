import SwiftUI

extension BrowserShortcutStore {
    func keyboardShortcut(
        for command: ShortcutCommand
    ) -> KeyboardShortcut? {
        shortcut(for: command).map(\.keyboardShortcut)
    }
}
