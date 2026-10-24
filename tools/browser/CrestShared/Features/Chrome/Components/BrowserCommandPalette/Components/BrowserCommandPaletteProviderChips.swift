import SwiftUI

/// While what is typed is still one word, every search provider it names or
/// starts to name, as a row of glass chips under the field: each with its
/// icon and the shortcut that enters it, on one line. The first is the one
/// Tab enters. Choosing one enters it.
struct BrowserCommandPaletteProviderChips: View {
    let model: BrowserCommandPaletteModel

    var body: some View {
        ScrollView(.horizontal) {
            GlassEffectContainer(spacing: CrestSpacing.small) {
                HStack(spacing: CrestSpacing.small) {
                    ForEach(Array(model.providerChips.enumerated()), id: \.element.name) { index, provider in
                        BrowserCommandPaletteProviderChip(
                            provider: provider, isOffered: index == 0, profileID: model.space?.profileID
                        ) {
                            model.enter(provider)
                        }
                    }
                }
                .padding(.horizontal, BrowserCommandPaletteMetrics.resultContentPadding)
                .padding(.vertical, CrestSpacing.small)
            }
        }
        .scrollIndicators(.hidden)
        .frame(height: BrowserCommandPaletteMetrics.providerChipRowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Search providers")
        .accessibilityIdentifier("command-palette-provider-chips")
    }
}

/// One provider among the palette's chips: its icon on a neutral plate and
/// the shortcut that enters it, or its name when it has none, with Tab's
/// glyph on the one Tab enters, on glass in its brand color.
private struct BrowserCommandPaletteProviderChip: View {
    let provider: SearchProvider
    let isOffered: Bool
    var profileID: UUID?
    let enter: () -> Void

    var body: some View {
        Button(action: enter) {
            BrowserPaletteChip(color: provider.color.color, showsCloseControl: false, isInteractive: true) {
                BrowserSearchProviderChipIcon(provider: provider, profileID: profileID)
                if let shortcut = provider.shortcuts.first {
                    Text(verbatim: shortcut)
                        .font(.callout.monospaced().weight(.semibold))
                } else {
                    Text(verbatim: provider.title)
                        .font(.callout.weight(.semibold))
                }
                if isOffered {
                    Image(systemName: "arrow.right.to.line")
                        .font(.caption2.weight(.semibold))
                        .accessibilityHidden(true)
                }
            }
            .lineLimit(1)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .help(provider.actionTitle)
        .accessibilityLabel(Text(verbatim: provider.actionTitle))
        .accessibilityHint(isOffered ? Text("Press Tab, enter your query, then press Return.") : Text(verbatim: ""))
        .accessibilityIdentifier("command-palette-provider-chip-\(provider.name)")
    }
}
