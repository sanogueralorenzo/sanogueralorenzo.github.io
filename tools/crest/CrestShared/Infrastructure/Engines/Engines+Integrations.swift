import Foundation

extension Engines {
    /// Choose the same engine a fresh navigation to the service would use.
    /// An unsupported engine must never borrow another engine's login session.
    func makeIntegrationSession(
        profileID: UUID, origin: URL, isAuthorized: @escaping @MainActor () -> Bool
    ) -> (any BrowserIntegrationSession)? {
        let kind = core.state.engines?.engines.first(where: \.isDefault)?.kind
        guard let kind, let binding = bindings[kind] else { return nil }
        return binding.makeIntegrationSession(profileID: profileID, origin: origin, isAuthorized: isAuthorized)
    }
}
