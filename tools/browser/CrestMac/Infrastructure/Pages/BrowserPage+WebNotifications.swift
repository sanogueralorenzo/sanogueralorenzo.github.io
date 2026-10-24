import AppKit
import Foundation

/// The notifications documents in a page post, which Crest shows as its own
/// through the system, whichever engine hosts the page. The core decides
/// whether one shows; a click brings the page forward before its document
/// hears it.
extension BrowserPage {
    // MARK: - Actions - Web notifications

    /// Shows `delivery`, which a document in the page posted, when the core
    /// lets the page's Space show the site's notifications and the system lets
    /// Crest show them. It never shows once Crest took the page's
    /// notifications down, or once `isPosted` says the document that posted it
    /// is gone, since either can happen while the system answers. A click
    /// brings the page's tab and Crest forward, then tells `clicked`. Answers
    /// whether it shows.
    func showWebNotification(
        _ delivery: BrowserHostedWebNotificationDelivery,
        isPosted: @escaping @MainActor () -> Bool = { true },
        clicked: @escaping @MainActor () -> Void
    ) async -> Bool {
        let generation = webNotificationGeneration
        let identifier = delivery.identifier
        let origin = delivery.origin
        let isShowable: @MainActor () -> Bool = { [weak self] in
            guard let self else { return false }
            return webNotificationGeneration == generation && isPosted()
                && permissionCenter.showsNotification(from: origin, in: spaceID)
        }
        guard isShowable(), let hostedNotificationCenter,
            await hostedNotificationCenter.currentAuthorization() == .authorized, isShowable()
        else { return false }
        do {
            try await hostedNotificationCenter.add(
                BrowserHostedWebNotificationDelivery(
                    identifier: identifier, title: String(delivery.title.prefix(200)),
                    body: String(delivery.body.prefix(1_000)), origin: origin, isSilent: delivery.isSilent)
            ) { [weak self] event in
                guard let self, webNotificationGeneration == generation, isPosted() else { return }
                switch event {
                case .clicked:
                    webNotificationIdentifiers.remove(identifier)
                    host?.activateNotificationSourcePage(self)
                    NSApp.activate()
                    clicked()
                }
            }
        } catch {
            return false
        }
        guard isShowable() else {
            await hostedNotificationCenter.remove(identifier: identifier)
            return false
        }
        webNotificationIdentifiers.insert(identifier)
        return true
    }

    /// Takes down a notification the document that posted it closed.
    func withdrawWebNotification(_ identifier: String) {
        webNotificationIdentifiers.remove(identifier)
        guard let hostedNotificationCenter else { return }
        Task { @MainActor in
            await hostedNotificationCenter.remove(identifier: identifier)
        }
    }

    /// Takes down every notification the page shows: its document is
    /// changing, or the page is leaving its engine.
    func removeWebNotifications() {
        webNotificationGeneration += 1
        let identifiers = webNotificationIdentifiers
        webNotificationIdentifiers.removeAll()
        guard let hostedNotificationCenter, !identifiers.isEmpty else { return }
        Task { @MainActor in
            for identifier in identifiers {
                await hostedNotificationCenter.remove(identifier: identifier)
            }
        }
    }

    /// Takes down what the page shows once the core no longer lets its Space
    /// show the notifications of the site the page shows.
    func removeWebNotificationsNoLongerShown() {
        guard let url = pageEngine.currentURL ?? live.documentURL, let origin = SiteOrigin(url: url),
            !permissionCenter.showsNotification(from: origin, in: spaceID)
        else { return }
        removeWebNotifications()
    }

    // MARK: - Actions - Engine notifications

    /// Shows a notification the page's engine says its document posted, for an
    /// engine that hosts the Notifications API itself, and tells the engine
    /// once the person clicks it or it will not show.
    func showEngineWebNotification(_ posted: WebNotificationPosted) {
        let enginePage = enginePage
        let delivery = BrowserHostedWebNotificationDelivery(
            identifier: engineWebNotificationIdentifier(posted.notificationID), title: posted.title,
            body: posted.body, origin: posted.origin, isSilent: posted.silent)
        Task { @MainActor [weak self, weak enginePage] in
            guard let self else { return }
            let shown = await showWebNotification(delivery) {
                enginePage?.answerWebNotification(posted.notificationID, with: .clicked)
            }
            if !shown {
                enginePage?.answerWebNotification(posted.notificationID, with: .declined)
            }
        }
    }

    /// The system's identity for the notification `notificationID` the page's
    /// engine says its document posted.
    func engineWebNotificationIdentifier(_ notificationID: String) -> String {
        "\(enginePage.id.uuidString).\(notificationID)"
    }
}
