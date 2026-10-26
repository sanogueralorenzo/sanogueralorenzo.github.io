import SwiftUI

struct BrowserCrestImportContent: View {
    let space: SpaceModel
    let favicons: FaviconAssets
    let matchedTabIDs: Set<UUID>
    var extensions: [ImportExtension] = []
    var extensionIcons: [String: NSImage] = [:]
    @Environment(CrestCore.self) private var core: CrestCore?

    /// No window shows an imported Space yet, so it highlights the tab the
    /// core would show first.
    private var highlightedTabID: UUID? { core?.fallbackTabID(in: space) }

    var body: some View {
        VStack(spacing: 0) {
            BrowserCrestImportChrome(space: space, highlightedTabID: highlightedTabID)

            if !extensions.isEmpty {
                BrowserImportSidebarExtensionStrip(extensions: extensions, icons: extensionIcons)
                    .padding(.horizontal, 10)
                    .padding(.top, 7)
            }

            if !space.pinnedTabs.isEmpty {
                BrowserCrestImportPinnedGrid(
                    space: space,
                    favicons: favicons,
                    matchedTabIDs: matchedTabIDs,
                    highlightedTabID: highlightedTabID
                )
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 6)
            }

            BrowserCrestImportSpaceHeader(space: space)
            BrowserCrestImportTabList(
                space: space,
                favicons: favicons,
                matchedTabIDs: matchedTabIDs,
                highlightedTabID: highlightedTabID
            )
            BrowserCrestImportSpaceSwitcher(space: space)
        }
    }
}
