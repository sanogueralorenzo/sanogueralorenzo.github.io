import Foundation

/// Hands an external-scheme navigation to the operating system, after consent.
/// Platform-neutral: the page that owns it supplies both the prompt and the one
/// call that actually opens a URL.
@MainActor
final class BrowserExternalSchemeCoordinator {
    typealias Prompt =
        @MainActor (
            SiteOrigin,
            URL,
            String
        ) async -> BrowserExternalSchemePromptResponse

    private let spaceID: UUID
    private let spaceName: String
    private let permissionCenter: BrowserSitePermissionCenter
    private let prompt: Prompt
    private let opensExternalURL: (URL) -> Void

    init(
        spaceID: UUID,
        spaceName: String,
        permissionCenter: BrowserSitePermissionCenter,
        prompt: @escaping Prompt,
        opensExternalURL: @escaping (URL) -> Void
    ) {
        self.spaceID = spaceID
        self.spaceName = spaceName
        self.permissionCenter = permissionCenter
        self.prompt = prompt
        self.opensExternalURL = opensExternalURL
    }

    /// Starts the hand-off. WebKit cannot wait for a prompt, so the caller has
    /// already cancelled the navigation and this returns immediately.
    func handOff(
        destinationURL: URL,
        trigger: BrowserPopupTrigger,
        origin: SiteOrigin?
    ) {
        Task { [weak self] in
            await self?.resolve(
                destinationURL: destinationURL,
                trigger: trigger,
                origin: origin
            )
        }
    }

    /// The hand-off itself, awaited. Split out so the consent rules can be
    /// exercised without a live prompt.
    func resolve(
        destinationURL: URL,
        trigger: BrowserPopupTrigger,
        origin: SiteOrigin?
    ) async {
        // Without an origin there is nothing to attribute or remember a choice
        // against, so the safe answer is to do nothing at all.
        guard let origin,
            let scheme = destinationURL.scheme?.lowercased(),
            !scheme.isEmpty
        else { return }

        // A hand-off launches another application, so an unapproved request
        // always pauses at Crest's prompt, whether or not a click started it.
        let decision = permissionCenter.decision(
            for: .externalApplications, origin: origin, detail: scheme, in: spaceID)
        var response = BrowserExternalSchemePromptResponse.answering(decision.verdict)
        if response == nil { response = await prompt(origin, destinationURL, spaceName) }
        guard let response else { return }
        if response.remembers {
            permissionCenter.setDecision(
                .grantPersistently,
                for: .externalApplications,
                origin: origin,
                detail: scheme,
                in: spaceID
            )
        }
        if response.opens { opensExternalURL(destinationURL) }
    }
}
