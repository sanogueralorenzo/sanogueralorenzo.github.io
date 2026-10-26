import SwiftUI

/// The lock or magnifying glass that stands in the leading slot while no live
/// site has claimed it.
struct BrowserSidebarAddressPlaceholderGlyph: View {
    let isSecure: Bool
    let metrics: BrowserSidebarAddressFieldMetrics

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ViewBuilder
    var body: some View {
        if let slot = metrics.leadingGlyphSlot {
            glyph
                .frame(width: slot, height: slot)
                .accessibilityHidden(true)
        } else {
            glyph
                .accessibilityHidden(true)
        }
    }

    private var glyph: some View {
        Image(systemName: isSecure ? "lock.fill" : "magnifyingglass")
            .font(metrics.leadingGlyphFont)
            .foregroundStyle(.secondary)
            .contentTransition(.symbolEffect(.replace))
            .animation(
                CrestMotion.contentState.unlessReducingMotion(reduceMotion),
                value: isSecure
            )
    }
}
