import Foundation

/// A Space's name and color, shared by its identity views.
struct BrowserSpaceIdentity: Equatable, Identifiable {
    // MARK: - Variables

    let id: UUID
    let profileID: UUID
    private(set) var name: String

    let color: SpaceColor

    /// Where the Space lives: its identity and profile.
    var assignment: BrowserSpaceRuntimeAssignment {
        BrowserSpaceRuntimeAssignment(spaceID: id, profileID: profileID)
    }

    // MARK: - Initializers

    /// A Space of the core's read model.
    @MainActor
    init(space: SpaceModel) {
        id = space.id
        profileID = space.profileID
        name = space.settings.name
        color = space.settings.color
    }

    init(dockSpace space: DockMenuSpace) {
        id = space.spaceID
        profileID = space.profileID
        name = space.name
        color = space.color
    }

    // MARK: - Actions - Drafting

    /// This identity as a draft shows it before it is saved, named `name`.
    func wearing(name: String) -> BrowserSpaceIdentity {
        var draft = self
        draft.name = name
        return draft
    }
}

/// A Space as a picker or identity view draws it, whatever form the caller
/// holds it in: the read model's Space, or the identity of one no session
/// holds yet, such as a setup draft.
@MainActor
protocol BrowserSpaceIdentifying: Identifiable where ID == UUID {
    var identity: BrowserSpaceIdentity { get }
}

extension BrowserSpaceIdentity: BrowserSpaceIdentifying {
    var identity: BrowserSpaceIdentity { self }
}

extension SpaceModel: BrowserSpaceIdentifying {
    var identity: BrowserSpaceIdentity { BrowserSpaceIdentity(space: self) }
}
