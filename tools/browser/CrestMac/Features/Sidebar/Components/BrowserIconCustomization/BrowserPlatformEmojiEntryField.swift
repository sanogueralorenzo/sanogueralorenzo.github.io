import SwiftUI

enum BrowserPlatformEmojiInput {
    static let presentation = BrowserNativeEmojiPickerPresentation.characterPalette
}

struct BrowserPlatformEmojiEntryField: View {
    @Binding var text: String
    let commit: () -> Void

    @State private var nativeTextInput = BrowserNativeEmojiTextInputController()
    private let fieldHeight: CGFloat = 22

    var body: some View {
        BrowserNativeEmojiTextField(
            text: $text, placeholder: "Search or Enter Emoji",
            controller: nativeTextInput, commit: commit
        )
        .frame(height: fieldHeight)
        BrowserNativeEmojiPickerButton(action: nativeTextInput.presentCharacterPalette)
    }
}

#if DEBUG
    #Preview("Enter an emoji") {
        @Previewable @State var text = "🌊"
        BrowserPlatformEmojiEntryField(text: $text, commit: {}).padding().frame(width: 320)
    }
#endif
