import Foundation

extension BrowserPlatformPage {
    /// Applies Crest's popup decision for the page's site to its engine.
    func synchronizePopupPermission(for url: URL? = nil) {
        let origin = (url ?? live.displayURL ?? pageEngine.currentURL)
            .flatMap(SiteOrigin.init(url:))
        let allowsAutomaticPopups =
            origin.map { permissionCenter.decision(for: .popups, origin: $0, in: spaceID).grants } ?? false
        // An engine's own popup blocker takes the site's own allowance, and
        // otherwise its default of blocking.
        enginePage.setSitePermission(.popups, allowed: allowsAutomaticPopups ? true : nil)
        recordPopupPermissionSynchronized(
            allowsAutomaticPopups: allowsAutomaticPopups,
            origin: origin
        )
    }

    /// The notice the Site Controls affordance draws, or nil when the running
    /// engine cannot report a blocked popup at all. An engine that does not
    /// declare `popups` must not present a control that can never populate.
    var blockedPopupNotice: BrowserBlockedPopupNotice? {
        guard pageEngine.registration.supports(.popups) else { return nil }
        return blockedPopupState.notice
    }

    /// A popup the engine's own blocker held back in the current document.
    func recordEngineBlockedPopup(pageURL: URL, documentIdentifier: String) {
        guard let origin = SiteOrigin(url: pageURL),
            !permissionCenter.decision(for: .popups, origin: origin, in: spaceID).grants
        else { return }
        var nextState = blockedPopupState
        guard nextState.recordBlockedAttempt(documentIdentifier: documentIdentifier, origin: origin) else { return }
        blockedPopupState = nextState
    }

    func beginBlockedPopupNavigation() {
        var nextState = blockedPopupState
        guard nextState.clearForNavigation() else { return }
        blockedPopupState = nextState
    }

    func recordAcceptedPopup() {
        var nextState = blockedPopupState
        guard nextState.clearAfterAllowedPopup() else { return }
        blockedPopupState = nextState
    }

    func allowAutomaticPopupsForBlockedSite() {
        guard let notice = blockedPopupState.notice,
            notice.status.offersAllow,
            let currentURL = live.displayURL ?? pageEngine.currentURL,
            SiteOrigin(url: currentURL) == notice.origin
        else { return }

        permissionCenter.setDecision(
            .grantPersistently,
            for: .popups,
            origin: notice.origin,
            in: spaceID
        )
        synchronizePopupPermission(for: currentURL)
        // An engine that kept the blocked popups opens them now; WebKit waits
        // for the page to try again.
        if enginePage.showBlockedPopups() { recordAcceptedPopup() }
    }

    func recordPopupPermissionSynchronized(
        allowsAutomaticPopups: Bool,
        origin: SiteOrigin?
    ) {
        guard let origin,
            blockedPopupState.notice?.origin == origin
        else { return }
        var nextState = blockedPopupState
        let didChange =
            allowsAutomaticPopups
            ? nextState.recordPermissionAllowed()
            : nextState.recordPermissionBlockedAgain()
        guard didChange else { return }
        blockedPopupState = nextState
    }
}
