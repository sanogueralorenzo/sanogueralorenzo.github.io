import SwiftUI

struct MobileArchiveList: View {
    let space: SpaceModel?
    let favicons: FaviconAssets
    let restoreArchivedTab: (UUID) -> Void

    var body: some View {
        Group {
            if let space {
                BrowserUtilityListContent(
                    surface: .archive,
                    space: space,
                    downloads: [],
                    searchText: "",
                    filter: .all,
                    actions: BrowserUtilityListActions(
                        restoreArchivedTab: { tabID, _ in
                            restoreArchivedTab(tabID)
                        }
                    ),
                    favicons: favicons
                )
            } else {
                ContentUnavailableView(
                    "No Space",
                    systemImage: "square.grid.2x2"
                )
            }
        }
    }
}
