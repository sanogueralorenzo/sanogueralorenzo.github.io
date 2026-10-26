import Foundation

extension WebKitEngineBinding {
    func makeIntegrationSession(
        profileID: UUID, origin: URL, isAuthorized: @escaping @MainActor () -> Bool
    ) -> (any BrowserIntegrationSession)? {
        guard origin.scheme == "https", origin.host != nil, origin.user == nil, origin.password == nil,
            origin.query == nil, origin.fragment == nil, isAuthorized()
        else { return nil }
        let session = WebKitIntegrationSession(
            store: store(profileID: profileID, isPrivate: false), origin: origin, isAuthorized: isAuthorized)
        integrationSessions = integrationSessions.filter { $0.value != nil }
        integrationSessions.append(WeakIntegrationSession(value: session, profileID: profileID))
        return session
    }

    func invalidateIntegrationSessions(profileID: UUID) {
        for session in integrationSessions where session.profileID == profileID { session.value?.invalidate() }
        integrationSessions.removeAll { $0.profileID == profileID || $0.value == nil }
    }
}
