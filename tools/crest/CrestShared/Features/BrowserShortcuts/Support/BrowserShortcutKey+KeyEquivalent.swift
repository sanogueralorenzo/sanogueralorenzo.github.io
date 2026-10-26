import SwiftUI

extension BrowserShortcutKey {
    var keyEquivalent: KeyEquivalent {
        switch self {
        case .character(let character):
            KeyEquivalent(character)
        case .special(let key):
            key.keyEquivalent
        }
    }
}
