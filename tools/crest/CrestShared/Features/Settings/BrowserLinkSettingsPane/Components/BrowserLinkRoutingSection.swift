import SwiftUI

struct BrowserLinkRoutingSection: View {
    let routes: [LinkRoute]
    let spaces: [SpaceModel]
    let selectedSpaceID: UUID
    let updateRoute: (UUID, BrowserLinkRouteFieldUpdate) -> Void
    let remove: (UUID) -> Void
    let move: (UUID, Int) -> Void
    let add: (UUID) -> Void

    var body: some View {
        Section {
            if routes.isEmpty {
                Text("No routes yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(routes.enumerated()), id: \.element.id) { index, route in
                    BrowserPlatformLinkRouteEditor(
                        route: route,
                        spaces: spaces,
                        canMoveUp: index > 0,
                        canMoveDown: index + 1 < routes.count,
                        update: { field in updateRoute(route.id, field) },
                        delete: { remove(route.id) },
                        moveUp: { move(route.id, -1) },
                        moveDown: { move(route.id, 1) }
                    )
                }
            }

            Button("New Route", systemImage: "plus") {
                add(selectedSpaceID)
            }
            .buttonStyle(.bordered)
        } header: {
            Text("Routing")
        } footer: {
            CrestFormFootnote("Routes apply to links from other apps. The first matching route wins.")
        }
    }
}
