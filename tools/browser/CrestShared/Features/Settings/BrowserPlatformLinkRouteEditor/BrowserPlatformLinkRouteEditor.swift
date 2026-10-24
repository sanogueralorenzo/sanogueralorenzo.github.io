import SwiftUI

struct BrowserPlatformLinkRouteEditor: View {
    let route: LinkRoute
    let spaces: [SpaceModel]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let update: (BrowserLinkRouteFieldUpdate) -> Void
    let delete: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    @Environment(\.browserSettingsUsesLiveSidebar) private var usesLiveSidebar

    var body: some View {
        if usesLiveSidebar {
            BrowserLinkRouteCard(
                route: route, spaces: spaces, canMoveUp: canMoveUp, canMoveDown: canMoveDown,
                update: update, delete: delete, moveUp: moveUp, moveDown: moveDown)
        } else {
            BrowserPlatformLinkRouteEditorContent(
                route: route,
                spaces: spaces,
                canMoveUp: canMoveUp,
                canMoveDown: canMoveDown,
                update: update,
                delete: delete,
                moveUp: moveUp,
                moveDown: moveDown
            )
        }
    }
}
