import SwiftUI

enum BrowserNativeEmojiPickerPresentation: Equatable, Sendable {
    case characterPalette
    case focusedTextInput

    static var current: Self {
        BrowserPlatformEmojiInput.presentation
    }

    var actionTitle: LocalizedStringKey {
        switch self {
        case .characterPalette: "Open Emoji Picker"
        case .focusedTextInput: "Use Emoji Keyboard"
        }
    }
}
