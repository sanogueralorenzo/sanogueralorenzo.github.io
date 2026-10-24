import SwiftUI

/// The Space's own controls, laid out by whoever holds them: the floating
/// capsule, or the system toolbar where the controls move to the side.
struct MobileSpaceActionButtons: View {
    let browser: BrowserStore
    let pages: MobileBrowserPageStore
    let utilityPresentationStyle: MobileBrowserSidebarUtilityPresentationStyle
    let configuration: MobileSpaceActionsConfiguration

    var body: some View {
        MobileSpacePrivateBrowsingButton(
            isPrivateBrowsing: browser.isPrivateBrowsing,
            accentColor: selectedAccentColor,
            action: configuration.togglePrivateBrowsing
        )
        MobileSpaceArchiveButton(
            utilityPresentationStyle: utilityPresentationStyle,
            archivedTabCount: browser.shownSpace?.archive.entries.count ?? 0,
            commonListsAreExpanded: configuration.commonListsAreExpanded,
            downloads: downloads,
            newDownloads: newDownloads,
            badgeColor: downloadBadgeColor,
            showArchive: configuration.showArchive,
            toggleCommonLists: configuration.toggleCommonLists,
            recordCommonListsTriggerFrame: configuration.recordCommonListsTriggerFrame
        )
        if utilityPresentationStyle == .sheet {
            MobileSpaceDownloadsButton(
                downloads: downloads,
                newDownloads: newDownloads,
                badgeColor: downloadBadgeColor,
                action: configuration.showDownloads
            )
        }
        MobileSpaceSettingsButton(action: configuration.showSettings)
    }

    private var downloads: [DownloadState] {
        guard let profileID = browser.shownSpace?.profileID else { return [] }
        return pages.downloadCenter.items(for: profileID)
    }

    private var newDownloads: [DownloadState] {
        guard let profileID = browser.shownSpace?.profileID else { return [] }
        return pages.downloadCenter.unacknowledgedItems(for: profileID)
    }

    private var selectedAccentColor: Color {
        browser.shownSpace.map(\.settings.look)?.colors.first?.color ?? .accentColor
    }

    private var downloadBadgeColor: Color {
        downloads.contains(where: { $0.phase.needsAttention }) ? .red : selectedAccentColor
    }
}
