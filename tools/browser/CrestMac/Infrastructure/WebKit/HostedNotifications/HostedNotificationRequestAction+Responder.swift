import Foundation

extension HostedNotificationRequestAction {
    /// Answers the request through `responder`, as this action says.
    @MainActor func respond(through responder: some BrowserHostedNotificationRequestResponder) async {
        switch kind {
        case .respondDefault: await responder.respondDefault()
        case .respondDenied: await responder.respondDenied()
        case .resolveSystemAuthorization: await responder.resolveSystemAuthorization()
        case .promptForSitePermission: await responder.promptForSitePermission()
        }
    }
}
