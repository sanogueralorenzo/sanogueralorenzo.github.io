@MainActor
protocol BrowserDeviceAuthenticating: AnyObject {
    func authenticate(reason: String) async throws -> Bool
}
