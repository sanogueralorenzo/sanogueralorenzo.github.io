import SwiftUI

/// Shared icon selection and emoji insertion for tabs, folders, Spaces, and split groups.
struct BrowserIconCustomizationView: View {
    let title: LocalizedStringKey
    let currentEmoji: String?
    var currentSystemSymbol: String? = nil
    var showsReset = false
    var resetTitle: LocalizedStringKey? = nil
    let setEmoji: (String) -> Void
    var setSystemSymbol: ((String) -> Void)? = nil
    var reset: (() -> Void)? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var mode = BrowserIconPickerMode.emoji
    @State private var category = BrowserEmojiCategory.people
    @State private var query = ""

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            BrowserIconPickerHeader(
                title: title, showsSystemSymbols: setSystemSymbol != nil,
                mode: $mode, showsReset: showsReset, resetTitle: resetTitle,
                reset: reset.map { action in
                    {
                        query = ""
                        action()
                    }
                })
            BrowserIconSearchField(mode: mode, query: $query, commitEmoji: commitInsertedEmoji)
            if mode == .systemSymbol {
                BrowserSystemSymbolCatalogGrid(
                    selection: currentSystemSymbol, query: query, select: selectSystemSymbol
                )
                .frame(height: 330)
            } else {
                BrowserIconSelectionGrid(
                    emojiChoices: visibleEmojiChoices, currentEmoji: currentEmoji, selectEmoji: selectEmoji)
            }
            if mode == .emoji, query.isEmpty {
                BrowserEmojiCategoryBar(category: $category, contentWidth: BrowserIconPickerLayout.contentWidth)
            }
        }
        .padding(CrestSpacing.large)
        .frame(width: BrowserIconPickerLayout.contentWidth + CrestSpacing.large * 2)
        .animation(resetAnimation, value: showsReset)
        .onAppear(perform: repairMode)
        .onChange(of: query, handlePotentialEmojiInsertion)
        .onChange(of: currentEmoji) { _, _ in repairMode() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("browser-icon-picker")
    }

    private var visibleEmojiChoices: [BrowserTabEmojiChoice] {
        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? BrowserTabEmojiChoices.choices(in: category)
            : BrowserTabEmojiChoices.matching(query)
    }

    private var resetAnimation: Animation? {
        CrestMotion.collection.unlessReducingMotion(reduceMotion)
    }

    private func repairMode() {
        guard setSystemSymbol != nil else {
            mode = .emoji
            return
        }
        mode = currentEmoji == nil ? .systemSymbol : .emoji
    }

    private func handlePotentialEmojiInsertion(_ oldValue: String, _ newValue: String) {
        guard mode == .emoji, let emoji = BrowserIconSymbol.normalizedEmoji(newValue) else { return }
        setEmoji(emoji)
        query = ""
    }

    private func commitInsertedEmoji() {
        guard let emoji = BrowserIconSymbol.normalizedEmoji(query) else { return }
        setEmoji(emoji)
        query = ""
    }

    private func selectEmoji(_ emoji: String) {
        query = ""
        mode = .emoji
        setEmoji(emoji)
    }

    private func selectSystemSymbol(_ symbol: String) {
        query = ""
        mode = .systemSymbol
        setSystemSymbol?(symbol)
    }
}
