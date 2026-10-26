import SwiftUI

enum BrowserEmojiVariantPickerMetrics {
    static let columnCount = 3
    static let cellSize = CrestLayout.minimumHitTarget
    static let spacing = CrestSpacing.extraSmall

    static func contentWidth(for variantCount: Int) -> CGFloat {
        let columns = min(max(variantCount, 1), columnCount)
        return CGFloat(columns) * cellSize
            + CGFloat(columns - 1) * spacing
    }
}

struct BrowserEmojiVariantPicker: View {
    let variants: [BrowserTabEmojiVariant]
    let selectEmoji: (String) -> Void

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(
                .fixed(BrowserEmojiVariantPickerMetrics.cellSize),
                spacing: BrowserEmojiVariantPickerMetrics.spacing
            ),
            count: min(
                max(variants.count, 1),
                BrowserEmojiVariantPickerMetrics.columnCount
            )
        )
    }

    var body: some View {
        LazyVGrid(
            columns: columns,
            spacing: BrowserEmojiVariantPickerMetrics.spacing
        ) {
            ForEach(variants) { variant in
                Button {
                    selectEmoji(variant.emoji)
                } label: {
                    Text(variant.emoji)
                        .font(.title3)
                        .frame(
                            width: BrowserEmojiVariantPickerMetrics.cellSize,
                            height: BrowserEmojiVariantPickerMetrics.cellSize
                        )
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(variant.name)
            }
        }
        .frame(
            width: BrowserEmojiVariantPickerMetrics.contentWidth(
                for: variants.count
            )
        )
        .padding(CrestSpacing.medium)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-emoji-variant-picker")
    }
}

#if DEBUG
    #Preview("Emoji variants") {
        BrowserEmojiVariantPicker(
            variants: [
                BrowserTabEmojiVariant(emoji: "👍", name: "Thumbs up"),
                BrowserTabEmojiVariant(emoji: "👍🏽", name: "Thumbs up: medium skin tone"),
                BrowserTabEmojiVariant(emoji: "👍🏿", name: "Thumbs up: dark skin tone"),
            ], selectEmoji: { _ in }
        ).padding()
    }
#endif
