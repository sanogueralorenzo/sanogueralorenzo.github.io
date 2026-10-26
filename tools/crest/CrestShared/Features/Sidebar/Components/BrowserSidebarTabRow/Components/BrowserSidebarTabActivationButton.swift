import SwiftUI

/// The part of a tab row that opens the tab: its favicon, its title, and the
/// whole strip of surface between them and the trailing control.
///
/// Shared with the split-group member lines, which draw the same label at
/// their own insets inside a group's container.
struct BrowserSidebarTabActivationButton: View {
    @Environment(CrestCore.self) private var core: CrestCore?
    let tab: TabStateModel
    let favicons: FaviconAssets
    let profileID: UUID
    let isSelected: Bool
    let isLoaded: Bool
    let metrics: BrowserSidebarTabRowMetrics
    /// The inset the label starts at. Part of the button rather than of the
    /// row, so the strip in front of the favicon opens the tab too. A nested
    /// line leaves it at zero: its container has already placed it.
    var leadingInset: CGFloat = 0
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            BrowserSidebarTabLabel(
                tab: tab, favicons: favicons, profileID: profileID, isSelected: isSelected,
                isLoaded: isLoaded, metrics: metrics, leadingInset: leadingInset)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: maxHeight)
        .contentShape(.rect)
        .accessibilityLabel(tab.shownTitle(in: isLoaded ? core?.state : nil))
        .accessibilityValue(BrowserChromeAccessibility.tabValue(isLoaded: isLoaded))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(BrowserTabAccessibilityID.row(tab.id))
    }

    /// A fixed-height row wants its activation area to fill the band; a row
    /// that grows with its label wants no height constraint at all.
    private var maxHeight: CGFloat? {
        metrics.fillsRowHeight ? .infinity : nil
    }
}
