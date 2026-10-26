import Foundation

extension BrowserSidebarUtilityCoordinator {
    /// Binds the sidebar's utility surfaces to the compact shell's page store.
    ///
    /// The compact shell has one page and a navigation stack around it, so a
    /// history entry is routed rather than opened in place and a restored tab
    /// goes through the shell's own selection. Finished files leave through the
    /// share sheet or the Files app, which is the store's export path.
    init(
        browser: BrowserStore,
        pages: MobileBrowserPageStore,
        spaceAccess: BrowserSpaceAccessController,
        selectTab: @escaping (UUID) -> Void,
        openURL: @escaping (URL) -> Void
    ) {
        self.init(
            browser: browser,
            downloadCenter: pages.downloadCenter,
            spaceAccess: spaceAccess,
            platformActions: BrowserSidebarUtilityPlatformActions(
                downloadDestinations: [.share, .files],
                openHistoryEntry: { url, _ in openURL(url) },
                selectRestoredTab: selectTab,
                openFinishedDownload: { item, destination in
                    guard let export = MobileBrowserFileExportDestination.exporting(destination) else { return }
                    pages.exportDownload(item.id, to: export)
                },
                cancelDownload: { itemID in
                    pages.cancelDownload(itemID)
                },
                clearDownload: { itemID in
                    pages.clearDownload(itemID)
                }
            )
        )
    }
}
