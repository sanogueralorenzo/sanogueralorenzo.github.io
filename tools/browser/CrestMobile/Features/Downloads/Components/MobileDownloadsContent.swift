import SwiftUI

struct MobileDownloadsContent: View {
    let space: SpaceModel?
    let downloads: [DownloadState]
    let actions: BrowserUtilityListActions
    let dismiss: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if let space {
                    BrowserUtilityListContent(
                        surface: .downloads,
                        space: space,
                        downloads: downloads,
                        searchText: "",
                        filter: .all,
                        actions: actions
                    )
                } else {
                    ContentUnavailableView("No Space", systemImage: "square.grid.2x2")
                }
            }
            .navigationTitle("Downloads")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss)
                }
            }
        }
        .frame(minWidth: 320, minHeight: 300)
        .presentationDetents([.medium, .large])
    }
}
