import SwiftUI

struct BrowserPlatformEmojiVariantModifier: ViewModifier {
    let choice: BrowserTabEmojiChoice
    @Binding var isPresented: Bool
    let selectEmoji: (String) -> Void

    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .contextMenu {
                ForEach(choice.variants) { variant in
                    Button {
                        selectEmoji(variant.emoji)
                    } label: {
                        Label {
                            Text(variant.name)
                        } icon: {
                            Text(variant.emoji)
                        }
                    }
                }
            }
            .accessibilityHint("Long press or open the context menu for skin tone variations.")
    }
}
