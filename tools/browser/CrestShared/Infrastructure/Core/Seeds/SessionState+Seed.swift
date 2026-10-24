import Foundation

extension SessionState.Seed {
    // MARK: - Initializers

    /// A session to seed a workspace with: `spaces` in order, opening on
    /// `defaultSpaceID`, with no Space deletion under way and no app
    /// preferences of its own. `disposableSeedMarker` marks the disposable
    /// first-install seed.
    init(spaces: [SpaceState.Seed], defaultSpaceID: UUID? = nil, disposableSeedMarker: UUID? = nil) {
        self.init(
            spaces: spaces, defaultSpaceID: defaultSpaceID, disposableSeedMarker: disposableSeedMarker,
            spaceDeletions: [], appPreferences: nil)
    }

    // MARK: - Actions - Reading

    /// The Space the seed holds with this identity.
    func space(id: UUID) -> SpaceState.Seed? {
        spaces.first { $0.id == id }
    }
}
