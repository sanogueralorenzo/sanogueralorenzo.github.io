@MainActor
final class BrowserPreviewAuthenticator: BrowserDeviceAuthenticating {
    private let result: Bool

    init(result: Bool) {
        self.result = result
    }

    func authenticate(reason _: String) async throws -> Bool {
        result
    }
}
