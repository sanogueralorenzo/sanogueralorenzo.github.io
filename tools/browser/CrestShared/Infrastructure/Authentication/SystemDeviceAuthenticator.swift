import Foundation
import LocalAuthentication

@MainActor
final class SystemBrowserDeviceAuthenticator: BrowserDeviceAuthenticating {
    func authenticate(reason: String) async throws -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = String(localized: "Cancel")

        var policyError: NSError?
        guard
            context.canEvaluatePolicy(
                .deviceOwnerAuthentication,
                error: &policyError
            )
        else {
            if let policyError {
                throw policyError
            }
            return false
        }

        return try await context.evaluatePolicy(
            .deviceOwnerAuthentication,
            localizedReason: reason
        )
    }
}
