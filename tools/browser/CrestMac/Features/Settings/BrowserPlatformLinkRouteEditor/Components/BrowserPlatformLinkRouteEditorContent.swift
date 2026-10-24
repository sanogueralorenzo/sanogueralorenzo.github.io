import SwiftUI

struct BrowserPlatformLinkRouteEditorContent: View {
    let route: LinkRoute
    let spaces: [SpaceModel]
    let canMoveUp: Bool
    let canMoveDown: Bool
    let update: (BrowserLinkRouteFieldUpdate) -> Void
    let delete: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void

    var body: some View {
        BrowserLinkRouteCard(
            route: route, spaces: spaces, canMoveUp: canMoveUp, canMoveDown: canMoveDown,
            update: update, delete: delete, moveUp: moveUp, moveDown: moveDown)
    }
}
