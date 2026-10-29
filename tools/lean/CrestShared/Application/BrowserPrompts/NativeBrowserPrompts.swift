import Foundation

/// Process-local questions. Credentials travel directly to WebKit and never
/// enter session state, persistence, generated messages or a change feed.
@MainActor
final class NativeBrowserPrompts {
    enum Failure: Error, Equatable {
        case unknownPrompt(UUID)
        case answerMismatch(UUID)
    }
    private enum Question {
        case authentication, scriptDialog, install
        case permission(PermissionQuestion)
    }
    private struct Waiting {
        weak var binding: WebKitEngineBinding?
        let pageID: UUID?
        let question: Question
    }
    private unowned let core: CrestCore
    private let notify: @MainActor (any CorePromptChange) -> Void
    private var waiting: [UUID: Waiting] = [:]
    private var depth = 0
    private var flushing = false
    private var effects: [@MainActor () -> Void] = []

    init(core: CrestCore, notify: (@MainActor (any CorePromptChange) -> Void)? = nil) {
        self.core = core
        self.notify = notify ?? { [weak core] in core?.promptsChanged([$0]) }
    }

    func report(_ event: some PromptEvent, from binding: WebKitEngineBinding) {
        if depth == 0 { core.drain() }
        guard core.engines.webKit === binding else { return }
        depth += 1
        defer { finishTurn() }
        event.apply(to: self, from: binding)
    }

    func send(_ intent: some PromptIntent) throws(Failure) {
        if depth == 0 { core.drain() }
        depth += 1
        defer { finishTurn() }
        try intent.apply(to: self)
    }

    /// Commit state before callbacks. Reentrant WebKit reports append work
    /// after the current settlement rather than presenting on its stack.
    private func finishTurn() {
        depth -= 1
        guard depth == 0, !flushing else { return }
        flush()
    }
    private func flush() {
        guard !flushing else { return }
        flushing = true
        var index = 0
        while index < effects.count {
            let effect = effects[index]
            index += 1
            effect()
        }
        effects.removeAll(keepingCapacity: true)
        flushing = false
    }
    private func emit(_ change: any CorePromptChange) {
        effects.append { [notify] in notify(change) }
        if depth == 0 { flush() }
    }

    private func asking(_ pageID: UUID?) -> PageStateModel? {
        guard let pageID, let page = core.state.pages[pageID], page.phase.holdsEnginePage else { return nil }
        return page
    }

    private func raise(
        _ id: UUID, pageID: UUID?, question: Question, from binding: WebKitEngineBinding,
        declining: @escaping @MainActor () -> Void, asked: any CorePromptChange
    ) {
        guard waiting[id] == nil else { return }
        if pageID != nil && asking(pageID) == nil {
            effects.append(declining)
            return
        }
        if let page = asking(pageID), case .permission(let permission) = question {
            let answer = decision(page.spaceID, permission)
            if !answer.asks || permission.permission.isAskedBySystem {
                effects.append {
                    SettlePermission(promptID: id, grants: !answer.denies, remembers: answer.isPersistent).perform(
                        on: binding)
                }
                return
            }
        }
        waiting[id] = Waiting(binding: binding, pageID: pageID, question: question)
        emit(asked)
    }

    func raise(_ event: AuthenticationChallenged, from binding: WebKitEngineBinding) {
        raise(
            event.promptID, pageID: event.pageID, question: .authentication, from: binding,
            declining: { SettleAuthentication(promptID: event.promptID, credential: nil).perform(on: binding) },
            asked: AuthenticationAsked(promptID: event.promptID, pageID: event.pageID, question: event.question))
    }
    func raise(_ event: ScriptDialogOpened, from binding: WebKitEngineBinding) {
        raise(
            event.promptID, pageID: event.pageID, question: .scriptDialog, from: binding,
            declining: {
                SettleScriptDialog(promptID: event.promptID, accepted: false, text: nil).perform(on: binding)
            },
            asked: ScriptDialogAsked(promptID: event.promptID, pageID: event.pageID, question: event.question))
    }
    func raise(_ event: PermissionRequested, from binding: WebKitEngineBinding) {
        raise(
            event.promptID, pageID: event.pageID, question: .permission(event.question), from: binding,
            declining: {
                SettlePermission(promptID: event.promptID, grants: false, remembers: false).perform(on: binding)
            },
            asked: PermissionAsked(promptID: event.promptID, pageID: event.pageID, question: event.question))
    }
    func raise(_ event: ExtensionInstallRequested, from binding: WebKitEngineBinding) {
        raise(
            event.promptID, pageID: nil, question: .install, from: binding,
            declining: {
                SettleExtensionInstall(promptID: event.promptID, accepted: false, withholdsSiteAccess: false).perform(
                    on: binding)
            },
            asked: ExtensionInstallAsked(promptID: event.promptID, windowID: event.windowID, question: event.question))
    }

    func withdraw(_ id: UUID, from binding: WebKitEngineBinding) {
        if waiting[id]?.binding === binding { settle(id) }
    }
    func prune() {
        let gone = waiting.filter { _, prompt in
            prompt.binding == nil || (prompt.pageID != nil && asking(prompt.pageID) == nil)
        }.map(\.key)
        for id in gone { settle(id) }
    }
    private func settle(_ id: UUID) {
        if waiting.removeValue(forKey: id) != nil { emit(PromptSettled(promptID: id)) }
    }
    private func prompt(_ id: UUID) throws(Failure) -> Waiting {
        guard let prompt = waiting[id] else { throw .unknownPrompt(id) }
        return prompt
    }
    private func decision(_ spaceID: UUID, _ question: PermissionQuestion) -> SitePermissionDecision {
        if question.permission.isMedia {
            return
                (try? core.query(CaptureDecision(spaceID: spaceID, origin: question.origin, media: question.permission)))?
                .decision ?? .ask
        }
        return
            (try? core.query(
                SiteDecision(spaceID: spaceID, origin: question.origin, permission: question.permission, detail: nil)))?
            .decision ?? .ask
    }

    func answer(_ action: AnswerAuthentication) throws(Failure) {
        let prompt = try prompt(action.promptID)
        guard case .authentication = prompt.question else { throw .answerMismatch(action.promptID) }
        waiting[action.promptID] = nil
        effects.append {
            guard let binding = prompt.binding else { return }
            SettleAuthentication(promptID: action.promptID, credential: action.credential).perform(on: binding)
        }
        emit(PromptSettled(promptID: action.promptID))
    }
    func answer(_ action: AnswerScriptDialog) throws(Failure) {
        let prompt = try prompt(action.promptID)
        guard case .scriptDialog = prompt.question else { throw .answerMismatch(action.promptID) }
        waiting[action.promptID] = nil
        effects.append {
            guard let binding = prompt.binding else { return }
            SettleScriptDialog(promptID: action.promptID, accepted: action.accepted, text: action.text).perform(
                on: binding)
        }
        emit(PromptSettled(promptID: action.promptID))
    }
    func answer(_ action: AnswerExtensionInstall) throws(Failure) {
        let prompt = try prompt(action.promptID)
        guard case .install = prompt.question else { throw .answerMismatch(action.promptID) }
        waiting[action.promptID] = nil
        effects.append {
            guard let binding = prompt.binding else { return }
            SettleExtensionInstall(
                promptID: action.promptID, accepted: action.accepted, withholdsSiteAccess: action.withholdsSiteAccess
            ).perform(on: binding)
        }
        emit(PromptSettled(promptID: action.promptID))
    }
    func answer(_ action: AnswerPermission) throws(Failure) {
        let prompt = try prompt(action.promptID)
        guard case .permission(let question) = prompt.question else { throw .answerMismatch(action.promptID) }
        waiting[action.promptID] = nil
        let pending = prompt.binding?.prompts.removeValue(forKey: action.promptID) as? WebKitPendingPermission
        var grants = action.grants
        if let page = asking(prompt.pageID) {
            let current = decision(page.spaceID, question)
            if current.denies {
                grants = false
            } else if action.remembers {
                _ = try? core.send(
                    DecideSitePermission(
                        spaceID: page.spaceID, origin: question.origin, permission: question.permission, detail: nil,
                        decision: grants ? .grantPersistently : .denyPersistently))
            }
        }
        let allowed = grants
        effects.append { pending?.answer(allowed) }
        emit(PromptSettled(promptID: action.promptID))
    }
}

extension CrestCore {
    func send(_ intent: some PromptIntent) throws(NativeBrowserPrompts.Failure) { try prompts.send(intent) }
}
