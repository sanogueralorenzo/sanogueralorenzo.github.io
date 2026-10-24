import SwiftUI

private struct BrowserReadableForegroundModifier: ViewModifier {
    let background: Color

    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        content.foregroundStyle(background.readableForeground(environment: environment))
    }
}

private struct BrowserTabResidencyModifier: ViewModifier {
    let isLoaded: Bool

    func body(content: Content) -> some View {
        let isDimmed = !isLoaded && BrowserDeviceAppearanceStore.shared.tabs.dimsUnloadedTabs
        content
            .saturation(isDimmed ? 0.3 : 1)
            .opacity(isDimmed ? 0.5 : 1)
    }
}

private struct CrestOptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let identifier, identifier.contains(where: { !$0.isWhitespace }) {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}

extension View {
    func browserReadableForeground(over background: Color) -> some View {
        modifier(BrowserReadableForegroundModifier(background: background))
    }

    /// Optionally fades what stands for a tab the shell is no longer holding in memory.
    ///
    /// Applied to the pieces that *describe* the tab — its favicon, its title —
    /// rather than to the row or tile as a whole, so a mark drawn over one of
    /// them can stay out of the treatment. An unloaded tab still holds its
    /// extension side panel, and the badge saying so keeps full strength.
    func browserTabResidency(isLoaded: Bool) -> some View {
        modifier(BrowserTabResidencyModifier(isLoaded: isLoaded))
    }

    /// Applies an identifier only when one is supplied, preserving any identifier
    /// already published by the wrapped control.
    func crestAccessibilityIdentifier(_ identifier: String?) -> some View {
        modifier(CrestOptionalAccessibilityIdentifier(identifier: identifier))
    }

    /// Keeps action menus consistent across Apple platforms. Every Crest-authored
    /// menu action supplies an icon when a meaningful symbol, Crest, or logo is
    /// available. Apply this to the action builder *inside* each `Menu` or
    /// `contextMenu`: native menu presentation is a boundary, so styling only the
    /// revealing control does not reliably reach submenu rows on macOS.
    func crestMenuActionLabelStyle() -> some View {
        labelStyle(.titleAndIcon)
    }
}
