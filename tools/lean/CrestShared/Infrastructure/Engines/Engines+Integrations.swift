import Foundation

extension Engines {
    func makeIntegrationSession(
        profileID: UUID, origin: URL, isAuthorized: @escaping @MainActor () -> Bool
    ) -> (any BrowserIntegrationSession)? {
        webKit?.makeIntegrationSession(profileID: profileID, origin: origin, isAuthorized: isAuthorized)
    }
}
