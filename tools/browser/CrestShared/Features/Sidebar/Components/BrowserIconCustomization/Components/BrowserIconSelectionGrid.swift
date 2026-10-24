import SwiftUI

struct BrowserIconSelectionGrid: View {
    let emojiChoices: [BrowserTabEmojiChoice]
    let currentEmoji: String?
    let selectEmoji: (String) -> Void

    @State private var variantChoice: BrowserTabEmojiChoice?

    @ViewBuilder
    var body: some View {
        if emojiChoices.count == 0 {
            Text("No Matching Emoji")
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: BrowserIconPickerLayout.contentWidth, height: BrowserIconPickerLayout.emptyGridHeight)
                .accessibilityIdentifier("browser-icon-picker-empty")
        } else {
            ScrollView {
                LazyVGrid(columns: BrowserIconPickerLayout.columns, spacing: BrowserIconPickerLayout.gridSpacing) {
                    ForEach(emojiChoices) { choice in
                        BrowserIconEmojiButton(
                            choice: choice, currentEmoji: currentEmoji,
                            variantChoice: $variantChoice, selectEmoji: selectEmoji)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(
                width: BrowserIconPickerLayout.contentWidth,
                height: BrowserIconPickerLayout.gridHeight(choiceCount: emojiChoices.count))
        }
    }

}
