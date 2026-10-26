import AppKit
import Foundation

/// The questions the core asks about the page, shown as sheets on its window
/// whichever engine hosts it, with the person's answers sent back to the core.
extension BrowserPage: BrowserPromptPresenting {
    // MARK: - Actions - Prompts

    func ask(_ asked: ScriptDialogAsked, dismissal: BrowserPromptDismissal) {
        let question = asked.question
        let request = URLRequest(
            url: URL(string: question.sourceURL) ?? pageEngine.currentURL ?? URL(fileURLWithPath: "/"))
        let corePage = corePage
        let promptID = asked.promptID
        scriptDialog = asked
        // Whoever answers, the person or an agent, the core settles the
        // question and its sheet closes.
        dismissal.attach { [weak self] in
            if self?.scriptDialog?.promptID == promptID { self?.scriptDialog = nil }
        }
        let reply: @MainActor @Sendable (Bool, String?) -> Void = { [weak self] accepted, text in
            if self?.scriptDialog?.promptID == promptID { self?.scriptDialog = nil }
            corePage.answer(AnswerScriptDialog(promptID: promptID, accepted: accepted, text: text))
        }
        question.kind.present(question, request: request, dismissal: dismissal, on: self, reply: reply)
    }

    func ask(_ asked: AuthenticationAsked, dismissal: BrowserPromptDismissal) {
        let corePage = corePage
        let promptID = asked.promptID
        guard let challenge = BrowserAuthenticationChallenge(asked.question) else {
            corePage.answer(AnswerAuthentication(promptID: promptID, credential: nil))
            return
        }
        let session = httpAuthenticationSession
        let presenter = dialogPresenter
        let spaceName = spaceName
        Task { @MainActor in
            let decision = await session.response(to: challenge) { prompt in
                await presenter.presentHTTPAuthentication(prompt: prompt, spaceName: spaceName, dismissal: dismissal)
            }
            corePage.answer(AnswerAuthentication(promptID: promptID, credential: decision.credential))
        }
    }

    func ask(_ asked: PermissionAsked, dismissal: BrowserPromptDismissal) {
        let question = asked.question
        let corePage = corePage
        let promptID = asked.promptID
        let requests = sitePermissionRequests
        let spaceName = spaceName
        Task { @MainActor [weak self] in
            var response = await requests.response(
                to: question.permission, origin: question.origin, topLevelOrigin: question.topLevelOrigin,
                spaceName: spaceName, dismissal: dismissal)
            // An Allow the system then refuses saves nothing, so the site
            // cannot gain the capability silently once the system allows it.
            if response.grants, await self?.systemConsent.consents(to: question.permission) != true {
                response = .denyOnce
            }
            corePage.answer(
                AnswerPermission(promptID: promptID, grants: response.grants, remembers: response.savedDecision != nil))
        }
    }

    /// Whether the system lets Crest use the person's location for the
    /// page's sites, asking them when it has not decided: through WebKit's
    /// location bridge when the page has one, else the system's own service.
    func systemAuthorizesLocation() async -> Bool {
        if let coordinator = webKitAdapter?.geolocationCoordinator { return await coordinator.systemAuthorizes() }
        let dialogs = dialogPresenter
        return await BrowserGeolocationSystemService().systemAuthorizes {
            await dialogs.recoverGeolocationSystemAuthorization()
        }
    }
}

/// Each kind of script dialog, shown as a sheet on the page's window.
extension BrowserPage: BrowserScriptDialogPresenting {
    /// The window the page's dialogs attach to: the page's own while the
    /// person can see it, or else, as when it is hidden or minimized, the
    /// window the presenter finds.
    private var dialogWindow: NSWindow? {
        guard let window = nativeView.window, window.isVisible, !window.isMiniaturized else { return nil }
        return window
    }

    func presentAlert(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal, reply: @escaping Reply
    ) {
        dialogPresenter.presentAlert(
            message: question.message, request: request, on: dialogWindow, dismissal: dismissal
        ) {
            reply(true, nil)
        }
    }

    func presentConfirm(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal, reply: @escaping Reply
    ) {
        dialogPresenter.presentConfirm(
            message: question.message, request: request, on: dialogWindow, dismissal: dismissal
        ) {
            reply($0, nil)
        }
    }

    func presentPrompt(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal, reply: @escaping Reply
    ) {
        dialogPresenter.presentPrompt(
            message: question.message, defaultText: question.defaultText, request: request, on: dialogWindow,
            dismissal: dismissal
        ) { answer in
            reply(answer != nil, answer)
        }
    }

    func presentBeforeUnload(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal, reply: @escaping Reply
    ) {
        dialogPresenter.presentBeforeUnload(request: request, on: dialogWindow, dismissal: dismissal) {
            reply($0, nil)
        }
    }
}
