import Foundation

/// The one route field a settings edit changes; the core applies it.
enum BrowserLinkRouteFieldUpdate: Equatable, Sendable {
    case isEnabled(Bool)
    case match(LinkRouteMatch)
    case pattern(String)
    case destinationSpaceID(UUID)

    /// The intent that changes this field of route `id`.
    func edit(of id: UUID) -> EditLinkRoute {
        switch self {
        case .isEnabled(let value):
            EditLinkRoute(routeID: id, isEnabled: value, match: nil, pattern: nil, destinationSpaceID: nil)
        case .match(let value):
            EditLinkRoute(routeID: id, isEnabled: nil, match: value, pattern: nil, destinationSpaceID: nil)
        case .pattern(let value):
            EditLinkRoute(routeID: id, isEnabled: nil, match: nil, pattern: value, destinationSpaceID: nil)
        case .destinationSpaceID(let value):
            EditLinkRoute(routeID: id, isEnabled: nil, match: nil, pattern: nil, destinationSpaceID: value)
        }
    }
}
