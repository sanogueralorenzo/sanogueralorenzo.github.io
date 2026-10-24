import Foundation

/// The questions the core asks about the page, shown as alerts over the
/// window, with the person's answers sent back to the core.
extension MobileBrowserPage: BrowserPromptPresenting {
    // MARK: - Actions - Prompts

    func ask(_ asked: ScriptDialogAsked, dismissal: BrowserPromptDismissal) {
        let question = asked.question
        let request = URLRequest(url: URL(string: question.sourceURL) ?? webView.url ?? URL(fileURLWithPath: "/"))
        let corePage = corePage
        let promptID = asked.promptID
        let reply: @MainActor @Sendable (Bool, String?) -> Void = { accepted, text in
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
        let spaceName = spaceName
        Task { @MainActor in
            let decision = await session.response(to: challenge) { prompt in
                await MobileBrowserDialogPresenter.presentHTTPAuthentication(
                    prompt: prompt, spaceName: spaceName, dismissal: dismissal)
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
}

/// Each kind of script dialog, shown as an alert over the window. A page
/// asking before it unloads is a confirmation like any other.
extension MobileBrowserPage: BrowserScriptDialogPresenting {
    func presentAlert(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal, reply: @escaping Reply
    ) {
        MobileBrowserDialogPresenter.presentAlert(message: question.message, request: request, dismissal: dismissal) {
            reply(true, nil)
        }
    }

    func presentConfirm(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal, reply: @escaping Reply
    ) {
        MobileBrowserDialogPresenter.presentConfirmation(
            message: question.message, request: request, dismissal: dismissal
        ) {
            reply($0, nil)
        }
    }

    func presentPrompt(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal, reply: @escaping Reply
    ) {
        MobileBrowserDialogPresenter.presentPrompt(
            message: question.message, defaultText: question.defaultText, request: request, dismissal: dismissal
        ) { answer in
            reply(answer != nil, answer)
        }
    }

    func presentBeforeUnload(
        _ question: ScriptDialogQuestion, request: URLRequest, dismissal: BrowserPromptDismissal, reply: @escaping Reply
    ) {
        presentConfirm(question, request: request, dismissal: dismissal, reply: reply)
    }
}
