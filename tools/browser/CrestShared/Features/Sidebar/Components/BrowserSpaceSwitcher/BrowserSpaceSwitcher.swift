import SwiftUI

/// The one control both shells move between Spaces with.
///
/// The two shells reached the switcher differently enough that they kept two
/// of them, but the difference was never styling — it was arrangement, and
/// arrangement follows from what the shell's reader can aim at. So there is
/// one switcher whose layout the shell's `BrowserInteractionCapabilities`
/// choose, and two shared arrangements underneath
/// it. Accessories are inputs the scrolling arrangement simply ignores.
struct BrowserSpaceSwitcher: View {
    // MARK: - Variables

    @Environment(BrowserSidebarInteractionState.self) private var sidebarInteraction
    private let appearance = BrowserDeviceAppearanceStore.shared

    let browser: BrowserStore

    /// Held directly rather than behind the sidebar's page seam, the way
    /// `BrowserSidebarUtilityCoordinator` holds it: the switcher issues no page
    /// commands, it only needs to know what the profile has downloaded.
    let downloadCenter: BrowserDownloadCenter
    let capabilities: BrowserInteractionCapabilities
    let selectSpace: (UUID) -> Void
    var accessories = BrowserSpaceSwitcherAccessories()

    // MARK: - Actions - Drawing

    var body: some View {
        switch capabilities.spaceSwitcherArrangement {
        case .compactStrip:
            BrowserSpaceSwitcherCompactStrip(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID,
                reorderState: sidebarInteraction.sidebarReorderState,
                metrics: metrics,
                iconSizing: appearance.spaceIconSizing,
                chosenIconScale: appearance.spaceIconScale,
                selectSpace: selectSpace,
                accessories: accessories,
                downloads: downloads
            )
        case .scrollingSegments:
            BrowserSpaceSwitcherScrollingSegments(
                spaces: spaces,
                selectedSpaceID: selectedSpaceID,
                reorderState: sidebarInteraction.sidebarReorderState,
                metrics: metrics,
                iconSizing: appearance.spaceIconSizing,
                chosenIconScale: appearance.spaceIconScale,
                selectSpace: selectSpace
            )
        }
    }

    /// Read only where an accessory is there to wear the badge, so a shell
    /// without one never touches the download center from here.
    private var downloads: BrowserSpaceSwitcherDownloads {
        guard accessories.commonLists != nil,
            let space = browser.shownSpace
        else { return .none }
        return BrowserSpaceSwitcherDownloads(
            items: downloadCenter.items(for: space.profileID),
            newItems: downloadCenter.unacknowledgedItems(for: space.profileID),
            badgeColor: space.settings.look.colors.first?.color ?? .accentColor
        )
    }

    private var spaces: [BrowserSpaceIdentity] {
        browser.availableSpaces.map(BrowserSpaceIdentity.init(space:))
    }

    private var selectedSpaceID: UUID {
        browser.selectedSpaceID
    }

    private var metrics: BrowserSpacePickerMetrics {
        capabilities.spacePickerMetrics
    }
}
