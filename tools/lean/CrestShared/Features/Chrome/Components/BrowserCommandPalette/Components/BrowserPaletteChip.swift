import SwiftUI

/// A scope's chip: its symbol and name on glass in the window's accent.
struct BrowserPaletteScopeChip: View {
    let scope: PaletteScope
    var showsCloseControl = false
    var isInteractive = false

    var body: some View {
        BrowserPaletteChip(color: .accentColor, showsCloseControl: showsCloseControl, isInteractive: isInteractive) {
            Image(systemName: scope.symbol)
                .font(.caption.weight(.semibold))
            Text(scope.title)
                .font(.callout.weight(.semibold))
                .lineLimit(1)
        }
    }
}

/// The capsule a palette chip draws its contents in: Liquid Glass tinted with
/// `color`, which fills it, so the glass picks the foreground that reads best
/// on it and the contents set none of their own. A chip a person can click
/// is `isInteractive`, so the glass answers the pointer and presses.
struct BrowserPaletteChip<Content: View>: View {
    let color: Color
    let showsCloseControl: Bool
    var isInteractive = false
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: CrestSpacing.extraSmall) {
            content
            if showsCloseControl {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
            }
        }
        .padding(.horizontal, CrestSpacing.small)
        .padding(.vertical, CrestSpacing.extraSmall)
        .glassEffect(.regular.tint(color).interactive(isInteractive), in: .capsule)
    }
}
