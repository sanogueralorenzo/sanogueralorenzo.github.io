import Foundation

/// What a window's multi-selection is made under: the Space the window
/// shows, with that Space's profile and access policy. A window drops its
/// selection once any of them changes.
struct BrowserSelectionScope: Equatable {
    // MARK: - Variables

    let spaceID: UUID
    /// The Space's profile, or nil while the core holds no such Space.
    let profileID: UUID?
    /// The Space's access policy, or nil while the core holds no such Space.
    let accessPolicy: SpaceAccessPolicy?

    // MARK: - Initializers

    /// The scope of the Space `spaceID` names, as `space`, its object in the
    /// read model, holds it now.
    @MainActor
    init(spaceID: UUID, space: SpaceModel?) {
        self.spaceID = spaceID
        profileID = space?.profileID
        accessPolicy = space?.settings.accessPolicy
    }
}
