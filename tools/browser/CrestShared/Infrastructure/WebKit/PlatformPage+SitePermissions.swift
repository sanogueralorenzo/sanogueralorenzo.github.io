import Foundation
import WebKit

/// A site's request for a capability WebKit enforces, answered through the
/// core.
extension BrowserPlatformPage {
    /// Answers WebKit's request that `origin`, in a page showing
    /// `topLevelOrigin`, use `permission`. The core answers from the Space's
    /// choices, or asks the person through the page's host. A granted capture
    /// is remembered for this page, so a later block can stop it.
    func answerPermission(
        _ permission: SitePermission, origin: SiteOrigin, topLevelOrigin: SiteOrigin,
        from webKitPage: WebKitEnginePage?,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void
    ) {
        guard let webKitPage else {
            decisionHandler(.deny)
            return
        }
        let question = PermissionQuestion(permission: permission, origin: origin, topLevelOrigin: topLevelOrigin)
        webKitPage.ask(question) { [weak self] grants in
            if grants, permission.isMedia {
                self?.sitePermissionSession.recordMediaGrant(permission, origin: origin)
            }
            decisionHandler(grants ? .grant : .deny)
        }
    }
}
