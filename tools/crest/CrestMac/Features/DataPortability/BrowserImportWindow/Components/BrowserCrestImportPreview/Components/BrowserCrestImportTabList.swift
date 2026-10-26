import SwiftUI

struct BrowserCrestImportTabList: View {
    let space: SpaceModel
    let favicons: FaviconAssets
    let matchedTabIDs: Set<UUID>
    let highlightedTabID: UUID?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(space.folders.models) { folder in
                    let tabs = space.savedTabs(in: folder.id)
                    if !tabs.isEmpty {
                        BrowserImportSidebarFolderRow(folder: folder)
                        ForEach(tabs) { tab in
                            row(tab)
                                .padding(.leading, 14)
                        }
                    }
                }

                ForEach(space.unfiledSavedTabs) { row($0) }

                if !space.savedTabs.isEmpty, !space.currentTabs.isEmpty {
                    Divider()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                }

                if !space.currentTabs.isEmpty {
                    Label("New Tab", systemImage: "plus")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 17)
                        .frame(
                            maxWidth: .infinity,
                            minHeight: 40,
                            alignment: .leading
                        )

                    ForEach(space.currentTabs) { row($0) }
                }
            }
        }
    }

    private func row(_ tab: TabStateModel) -> some View {
        BrowserImportSidebarResultTabRow(
            tab: tab,
            favicons: favicons,
            profileID: space.profileID,
            isSelected: tab.id == highlightedTabID,
            isMatched: matchedTabIDs.contains(tab.id)
        )
    }
}
