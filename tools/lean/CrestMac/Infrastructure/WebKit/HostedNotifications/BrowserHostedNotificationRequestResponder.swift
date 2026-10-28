import Foundation

/// Answers a document's notification permission request the way the core's
/// `HostedNotificationRequestAction` says, one method per action.
@MainActor
protocol BrowserHostedNotificationRequestResponder {
    func respondDefault() async
    func respondDenied() async
    func resolveSystemAuthorization() async
    func promptForSitePermission() async
}
