import SwiftUI

/// Chooses the emoji an emblem draws.
struct BrowserCrestStudioEmojiEmblemControls: View {
    @Binding var emoji: String
    @Binding var choosesEmoji: Bool

    var body: some View {
        BrowserArtworkPickerButton(title: "Emoji", detail: Text("Change emoji")) {
            choosesEmoji = true
        } artwork: {
            Text(emoji)
        }
        .accessibilityLabel("Choose Emoji")
        .accessibilityValue(emoji)
        .browserIconCustomizationPopover(
            .init(
                isPresented: $choosesEmoji, title: "Emblem", currentEmoji: emoji,
                setEmoji: { emoji = $0 }))
    }
}
