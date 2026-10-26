import SwiftUI

struct BrowserSiteExtensionsSection: View {
    let actions: [BrowserExtensionActionPresentation]
    let manageExtensions: () -> Void
    let perform: (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) -> Void
    let togglePinned: (BrowserExtensionActionPresentation) -> Void
    var presentMenu:
        (BrowserExtensionActionPresentation, BrowserExtensionPopupAnchor?) ->
            Void = { _, _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: CrestSpacing.medium) {
            BrowserSiteExtensionsHeader(
                manageExtensions: manageExtensions
            )
            if actions.isEmpty {
                Label(
                    "No extension actions for this page",
                    systemImage: "puzzlepiece.extension"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                actionGrid
            }
        }
    }

    private var actionGrid: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(
                    .flexible(),
                    spacing: BrowserSiteControlMetrics.extensionGridSpacing
                ),
                count: BrowserSiteControlMetrics.extensionColumnCount
            ),
            spacing: BrowserSiteControlMetrics.extensionGridSpacing
        ) {
            ForEach(actions) { action in
                BrowserSiteExtensionActionButton(
                    action: action,
                    perform: { perform(action, $0) },
                    togglePinned: { togglePinned(action) },
                    presentMenu: { presentMenu(action, $0) }
                )
            }
        }
    }
}
