import SwiftUI

/// The part of a tab row that opens the tab: its favicon, its title, and the
/// whole strip of surface between them and the trailing control.
///
/// Shared with the split-group member lines, which draw the same label at
/// their own insets inside a group's container.
struct BrowserSidebarTabActivationButton: View {
    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction
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
    let restoreSavedLocation: (() -> Void)?
    let iconCustomization: BrowserIconCustomizationPresentation
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            BrowserSidebarTabLabel(
                tab: tab, favicons: favicons, profileID: profileID, isSelected: isSelected,
                isLoaded: isLoaded, metrics: metrics, leadingInset: leadingInset,
                restoreSavedLocation: restoreSavedLocation, faviconPrimaryClick: faviconPrimaryClick)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, maxHeight: maxHeight)
        .contentShape(.rect)
        #if os(macOS)
            .simultaneousGesture(
                TapGesture(count: 2).onEnded {
                    guard tab.placement == .saved else { return }
                    restoreSavedLocation?()
                }
            )
        #endif
        .overlay(alignment: .leading) {
            Color.clear
                .frame(
                    width: metrics.faviconSlot?.width ?? 18,
                    height: metrics.faviconSlot?.glyphSize ?? 18
                )
                .padding(.leading, leadingInset)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
                .browserIconCustomizationPopover(iconCustomization, arrowEdge: iconPickerArrowEdge)
        }
        .accessibilityLabel(tab.shownTitle(in: isLoaded ? core?.state : nil))
        .accessibilityValue(BrowserChromeAccessibility.tabValue(isLoaded: isLoaded))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(BrowserTabAccessibilityID.row(tab.id))
    }

    private var iconPickerArrowEdge: Edge? {
        #if os(macOS)
            .trailing
        #else
            // Let the system use the available space on either side of the
            // sidebar. A forced side arrow can clip the picker at the screen edge.
            nil
        #endif
    }

    private var faviconPrimaryClick: (() -> Void)? {
        #if os(macOS)
            guard BrowserAppPreferenceStore.shared.returnsToSavedURLOnFaviconClick,
                tab.placement == .saved, tab.isAwayFromSavedAddress,
                let restoreSavedLocation
            else { return nil }
            return {
                guard !sidebarInteraction.sidebarReorderState.suppressesActivation else { return }
                restoreSavedLocation()
            }
        #else
            nil
        #endif
    }

    /// A fixed-height row wants its activation area to fill the band; a row
    /// that grows with its label wants no height constraint at all.
    private var maxHeight: CGFloat? {
        metrics.fillsRowHeight ? .infinity : nil
    }
}
