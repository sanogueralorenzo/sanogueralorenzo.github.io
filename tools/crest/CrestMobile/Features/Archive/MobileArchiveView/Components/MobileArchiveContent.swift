import SwiftUI

struct MobileArchiveContent: View {
    let space: SpaceModel?
    let favicons: FaviconAssets
    let restoreArchivedTab: (UUID) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            MobileArchiveList(
                space: space,
                favicons: favicons,
                restoreArchivedTab: restoreAndDismiss
            )
            .navigationTitle("\(space?.settings.name ?? "Space") Archive")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
    }

    private func restoreAndDismiss(_ tabID: UUID) {
        restoreArchivedTab(tabID)
        dismiss()
    }
}
