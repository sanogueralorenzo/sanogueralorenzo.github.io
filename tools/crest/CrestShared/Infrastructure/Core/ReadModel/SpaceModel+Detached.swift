import Foundation

extension SpaceModel {
    // MARK: - Actions - Building

    /// The Spaces `session` opens as, repaired and resolved by the core and
    /// held by no workspace: what a preview, or a draft before it is saved,
    /// shows. Nothing the core publishes ever reaches them.
    static func detached(_ session: SessionState.Seed) -> [SpaceModel] {
        do {
            return try CrestCore.answer(DetachedSession(seed: session)).spaces.map(SpaceModel.init)
        } catch {
            preconditionFailure("The core must open a seed built for a preview or a draft: \(error)")
        }
    }

    /// The Space `space` opens as alone in a session, held by no workspace.
    /// See `detached(_:)`.
    static func detached(_ space: SpaceState.Seed) -> SpaceModel {
        detached(SessionState.Seed(spaces: [space]))[0]
    }
}
