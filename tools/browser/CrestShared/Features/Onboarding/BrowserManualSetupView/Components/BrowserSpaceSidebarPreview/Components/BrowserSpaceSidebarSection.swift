import SwiftUI

struct BrowserSpaceSidebarSection: View {
    let title: String
    let tabs: [TabStateModel]
    let favicons: FaviconAssets
    let profileID: UUID
    let selectedTabID: UUID?

    var body: some View {
        if !tabs.isEmpty {
            VStack(
                alignment: .leading,
                spacing: BrowserManualSetupSidebarPreviewMetrics.sectionSpacing
            ) {
                Text(title)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(
                        .horizontal,
                        BrowserManualSetupSidebarPreviewMetrics
                            .sectionHorizontalPadding
                    )
                ForEach(tabs) { tab in
                    BrowserSpaceSidebarTabRow(
                        tab: tab,
                        favicons: favicons,
                        profileID: profileID,
                        isSelected: tab.id == selectedTabID
                    )
                }
            }
        }
    }
}
