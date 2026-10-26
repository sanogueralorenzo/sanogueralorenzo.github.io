import SwiftUI

struct BrowserSourceImportSavedTabs: View {
    let title: LocalizedStringResource
    let review: BrowserImportSpaceReview
    let sections: BrowserSourceImportPreviewSections
    let overflowTabIDs: Set<UUID>
    let duplicateTabIDs: Set<UUID>
    let duplicateDestinationName: String?
    let setIncluded: (UUID, Bool) -> Void
    let setSectionIncluded: (Set<UUID>, Bool) -> Void
    let setPlacement: (UUID, TabPlacement) -> Void

    @ViewBuilder
    var body: some View {
        if !sections.savedTabs.isEmpty {
            BrowserSourceImportSectionHeader(
                title: title,
                tabs: sections.savedTabs,
                includedTabIDs: review.includedTabIDs,
                setIncluded: setSectionIncluded
            )
            .padding(.horizontal, 13)

            ForEach(review.sourceSpace.folders.models) { folder in
                let tabs = sections.savedTabsByFolderID[folder.id, default: []]
                if !tabs.isEmpty {
                    BrowserImportSidebarFolderRow(folder: folder)
                    ForEach(tabs) { tab in
                        tabRow(tab)
                            .padding(.leading, 14)
                    }
                }
            }

            ForEach(sections.unfiledSavedTabs) { tabRow($0) }
        }
    }

    private func tabRow(_ tab: TabStateModel) -> some View {
        BrowserSourceImportTabRow(
            review: review,
            tab: tab,
            overflowTabIDs: overflowTabIDs,
            duplicateTabIDs: duplicateTabIDs,
            duplicateDestinationName: duplicateDestinationName,
            setIncluded: setIncluded,
            setPlacement: setPlacement
        )
    }
}
