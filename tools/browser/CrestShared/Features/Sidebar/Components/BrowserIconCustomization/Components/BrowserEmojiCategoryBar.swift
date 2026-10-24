import SwiftUI

struct BrowserEmojiCategoryBar: View {
    @Binding var category: BrowserEmojiCategory
    let contentWidth: CGFloat

    var body: some View {
        VStack(spacing: CrestSpacing.small) {
            Divider()
                .padding(.horizontal, CrestSpacing.extraSmall)

            ScrollView(.horizontal) {
                HStack(spacing: CrestSpacing.extraSmall) {
                    ForEach(BrowserEmojiCategory.all) { option in
                        Button {
                            category = option
                        } label: {
                            Image(systemName: option.symbol)
                                .frame(
                                    width: CrestLayout.minimumHitTarget,
                                    height: CrestLayout.minimumHitTarget
                                )
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(
                            category == option
                                ? Color.accentColor : Color.secondary
                        )
                        .background(
                            category == option ? CrestColor.hover : .clear,
                            in: .rect(cornerRadius: CrestRadius.compact)
                        )
                        .help(Text(option.title))
                        .accessibilityLabel(Text(option.title))
                        .accessibilityValue(
                            category == option ? "Selected" : ""
                        )
                    }
                }
                .frame(
                    minWidth: contentWidth - CrestSpacing.small * 2,
                    alignment: .center
                )
            }
            .contentMargins(
                .horizontal,
                CrestSpacing.small,
                for: .scrollContent
            )
            .scrollIndicators(.hidden)
        }
        .frame(width: contentWidth)
        .accessibilityIdentifier("browser-emoji-category-bar")
    }

}

#if DEBUG
    #Preview("Choose a category") {
        @Previewable @State var category: BrowserEmojiCategory = .nature
        BrowserEmojiCategoryBar(category: $category, contentWidth: 320).padding()
    }
#endif
