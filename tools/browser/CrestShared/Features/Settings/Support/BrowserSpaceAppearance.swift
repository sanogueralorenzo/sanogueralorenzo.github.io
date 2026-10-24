import Foundation

/// How a Space looks, held apart from it, for the appearance previews that
/// dress a sample sidebar in its look: its identity and look, and the folder
/// whose color and icon the sample folder wears. Read once from the read
/// model's Space, or dressed in a draft's live look before it is saved.
struct BrowserSpaceAppearance: Equatable, Identifiable {
    // MARK: - Variables

    let identity: BrowserSpaceIdentity
    /// The Space's first folder, or nil for a Space that holds none.
    let leadingFolder: FolderState?

    var id: UUID { identity.id }
    var branding: SpaceBranding { identity.branding }

    // MARK: - Initializers

    /// A Space of the read model.
    @MainActor
    init(space: SpaceModel) {
        identity = space.identity
        leadingFolder = space.folders.models.first?.value
    }

    /// A Space known only by its identity, holding no folder.
    init(identity: BrowserSpaceIdentity) {
        self.identity = identity
        leadingFolder = nil
    }

    private init(identity: BrowserSpaceIdentity, leadingFolder: FolderState?) {
        self.identity = identity
        self.leadingFolder = leadingFolder
    }

    // MARK: - Actions - Drafting

    /// This Space as a draft shows it before it is saved: named `name` and
    /// wearing `branding` and `symbol`.
    func wearing(_ branding: SpaceBranding, symbol: String, name: String) -> BrowserSpaceAppearance {
        BrowserSpaceAppearance(
            identity: identity.wearing(branding, symbol: symbol, name: name), leadingFolder: leadingFolder)
    }
}
