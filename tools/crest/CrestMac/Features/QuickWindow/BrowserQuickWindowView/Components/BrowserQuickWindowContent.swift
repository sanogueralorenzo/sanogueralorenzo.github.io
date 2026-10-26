import SwiftUI

struct BrowserQuickWindowContent: View {
    let model: BrowserQuickWindowModel
    let spaceAccess: BrowserSpaceAccessController
    let dismiss: () -> Void
    let openBrowserWindow: () -> Void

    var body: some View {
        Group {
            if let space = model.spaceModel,
                spaceAccess.isLocked(space)
            {
                BrowserSpaceAccessView(
                    space: space,
                    spaces: model.availableSpaceModels,
                    accessController: spaceAccess,
                    selectSpace: selectLockedSpace
                )
            } else if model.spaceModel != nil {
                BrowserQuickWindowUnlockedContent(
                    model: model,
                    spaceAccess: spaceAccess,
                    dismiss: dismiss,
                    openBrowserWindow: openBrowserWindow
                )
            } else {
                ContentUnavailableView(
                    "Space Unavailable",
                    systemImage: "square.grid.2x2",
                    description: Text(
                        "This Quick Window cannot reconnect to its original browsing profile."
                    )
                )
            }
        }
    }

    private func selectLockedSpace(
        _ assignment: BrowserSpaceRuntimeAssignment
    ) {
        model.selectSpace(assignment)
    }
}
