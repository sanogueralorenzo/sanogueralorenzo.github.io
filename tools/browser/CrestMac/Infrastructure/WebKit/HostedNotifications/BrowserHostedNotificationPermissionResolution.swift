import Foundation
import WebKit

/// One document's notification permission request on the page, answered the
/// way the core's action for the site's decision says.
@MainActor
struct BrowserHostedNotificationPermissionResolution: BrowserHostedNotificationRequestResponder {
    // MARK: - Variables

    let page: BrowserPage
    let requestID: String
    let origin: SiteOrigin
    let hasUserActivation: Bool
    let documentIdentifier: String
    let frame: WKFrameInfo

    /// The site's notification decision now.
    private var decision: SitePermissionDecision {
        page.permissionCenter.decision(for: .notifications, origin: origin, in: page.spaceID)
    }

    /// Whether the document that asked is still the page's.
    private var isCurrent: Bool {
        page.isCurrentHostedNotificationDocument(documentIdentifier, origin: origin)
    }

    // MARK: - Actions - Responses

    func respondDefault() async {
        respond(.prompt)
    }

    func respondDenied() async {
        respond(.denied)
    }

    func resolveSystemAuthorization() async {
        await page.sendHostedNotificationPermission(
            requestID: requestID,
            origin: origin,
            requestsSystemAuthorization: hasUserActivation,
            documentIdentifier: documentIdentifier,
            frame: frame
        )
    }

    func promptForSitePermission() async {
        let generation = page.sitePermissionRequests.generation
        // The core asks the person and records what they ask it to
        // remember; the system's consent still decides what the page hears.
        let grants =
            await page.webKitAdapter?.webKitPage.ask(
                PermissionQuestion(permission: .notifications, origin: origin, topLevelOrigin: origin)) ?? false
        guard isCurrent else { return }
        guard generation == page.sitePermissionRequests.generation else { return }
        guard grants else {
            // A block the person asked the core to remember denies the
            // site; a decline that saves nothing leaves it free to ask.
            respond(decision.denies ? .denied : .prompt)
            return
        }
        guard await page.authorizedForSystemNotifications(requestIfNeeded: true) else {
            respond(.denied)
            return
        }
        guard isCurrent else { return }
        guard generation == page.sitePermissionRequests.generation else {
            await page.sendHostedNotificationPermission(
                requestID: requestID, origin: origin,
                requestsSystemAuthorization: false,
                documentIdentifier: documentIdentifier, frame: frame
            )
            return
        }
        guard !decision.denies else {
            respond(.denied)
            return
        }
        // A granted request is remembered for the session at least; a
        // grant the person asked the core to remember is already kept.
        if !decision.grants {
            page.permissionCenter.setDecision(.grantForSession, for: .notifications, origin: origin, in: page.spaceID)
        }
        respond(.granted)
    }

    private func respond(_ permission: BrowserWebPermissionState) {
        page.sendHostedNotificationPermissionResponse(
            requestID: requestID,
            permission: permission,
            documentIdentifier: documentIdentifier,
            origin: origin,
            frame: frame
        )
    }
}
