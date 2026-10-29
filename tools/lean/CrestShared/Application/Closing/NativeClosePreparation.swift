import Foundation

/// One process-local close preparation. Page ownership stays with the session;
/// checking a page never releases it. State commits before WebKit callbacks.
@MainActor
final class NativeClosePreparation {
    enum Failure: Error, Equatable {
        case preparationUnderway(UUID)
        case unknownPrompt(UUID)
        case spaceDeletionUnderway(SpaceDeletionUnderway)
    }
    typealias Check = @MainActor (UUID, @escaping @MainActor (Bool) -> Void) -> Void
    private final class Preparation {
        let id: UUID
        let quits: Bool
        var pending: ArraySlice<UUID>
        var asked: [UUID: Int64] = [:]
        var awaiting: UUID?
        var promptID: UUID?
        let completion: @MainActor (Bool) -> Void
        init(id: UUID, quits: Bool, pages: [UUID], completion: @escaping @MainActor (Bool) -> Void) {
            self.id = id
            self.quits = quits
            pending = pages[...]
            self.completion = completion
        }
    }
    private unowned let core: CrestCore
    private let check: Check
    private let notify: @MainActor (any CorePromptChange) -> Void
    private var underway: Preparation?
    private var acceptedQuit = false
    private var depth = 0
    private var flushing = false
    private var effects: [@MainActor () -> Void] = []
    var isQuitting: Bool { acceptedQuit || underway?.quits == true }

    init(core: CrestCore, check: Check? = nil, notify: (@MainActor (any CorePromptChange) -> Void)? = nil) {
        self.core = core
        self.notify = notify ?? { [weak core] in core?.promptsChanged([$0]) }
        self.check =
            check ?? { [weak core] id, answer in
                #if os(macOS)
                    if let page = core?.engines.webKit?.page(id) {
                        page.engine.prepareToClose(completion: answer)
                        return
                    }
                #endif
                answer(true)
            }
    }
    func prepare(_ request: some CloseRequest, completion: @escaping @MainActor (Bool) -> Void) throws(Failure) {
        if depth == 0 { core.drain() }
        depth += 1
        defer { finishTurn() }
        let targets = try request.pages(in: self)
        var seen: Set<UUID> = []
        let closing = targets.filter { seen.insert($0).inserted }
        if !request.quits && closing.allSatisfy({ asking($0) == nil }) {
            effects.append { completion(true) }
            return
        }
        if let underway { throw .preparationUnderway(underway.id) }
        underway = Preparation(id: request.requestID, quits: request.quits, pages: closing, completion: completion)
        advance()
    }
    func allPagesForQuit() throws(Failure) -> [UUID] {
        let barriers = core.websiteData.quitBarriers
        if !barriers.isEmpty { throw .spaceDeletionUnderway(SpaceDeletionUnderway(spaceIDs: barriers)) }
        return core.state.pageOrder
    }
    func pagesForWindows(_ windows: [UUID]) -> [UUID] {
        let closing = Set(windows)
        let open = core.state.windows.values
        let ending = Set(open.filter { closing.contains($0.id) }.map(\.workspaceID)).filter { id in
            core.state.workspaces[id].map { $0.kind != .persistent } == true
                && !open.contains { $0.workspaceID == id && !closing.contains($0.id) }
        }
        return core.state.pageOrder.filter { id in
            guard let page = core.state.pages[id] else { return false }
            let kind = core.state.workspaces[page.workspaceID]?.kind
            let goesWithWindow =
                kind.map { core.platform != .desktop || $0 != .persistent } ?? true
            return closing.contains(page.windowID) && goesWithWindow || ending.contains(page.workspaceID)
        }
    }
    private func asking(_ id: UUID) -> PageStateModel? {
        guard let page = core.state.pages[id], page.phase == .live else { return nil }
        return page
    }
    func prune() {
        guard let underway, let id = underway.awaiting, asking(id) == nil else { return }
        depth += 1
        defer { finishTurn() }
        underway.awaiting = nil
        advance()
    }
    private func advance() {
        guard let current = underway else { return }
        while let id = current.pending.popFirst() {
            guard let page = asking(id) else { continue }
            current.awaiting = id
            current.asked[id] = page.documents
            effects.append { [weak self] in
                guard let self, underway === current, current.awaiting == id else { return }
                guard asking(id) != nil else {
                    prune()
                    return
                }
                check(id) { [weak self] in self?.answer(page: id, request: current, proceeds: $0) }
            }
            return
        }
        if current.asked.contains(where: { id, documents in
            core.state.pages[id].map { $0.documents != documents } ?? false
        }) {
            finish(false)
            return
        }
        let live = core.state.downloads.filter { $0.phase.isLive }.count
        if current.quits && live > 0 {
            let prompt = UUID()
            current.promptID = prompt
            emit(QuitWithDownloadsAsked(promptID: prompt, requestID: current.id, liveDownloads: live))
            return
        }
        finish(true)
    }
    private func answer(page: UUID, request: Preparation, proceeds: Bool) {
        if depth == 0 { core.drain() }
        depth += 1
        defer { finishTurn() }
        guard let current = underway, current === request, current.awaiting == page else { return }
        current.awaiting = nil
        if proceeds { advance() } else { finish(false) }
    }
    func answer(_ action: AnswerQuitWithDownloads) throws(Failure) {
        if depth == 0 { core.drain() }
        depth += 1
        defer { finishTurn() }
        guard underway?.promptID == action.promptID else { throw .unknownPrompt(action.promptID) }
        finish(action.quits)
    }
    private func finish(_ allowed: Bool) {
        guard let current = underway else { return }
        underway = nil
        if current.quits && allowed {
            acceptedQuit = true
            _ = try? core.send(AcceptQuit())
        }
        if let prompt = current.promptID { emit(PromptSettled(promptID: prompt)) }
        effects.append { current.completion(allowed) }
    }
    private func emit(_ change: any CorePromptChange) { effects.append { [notify] in notify(change) } }
    private func finishTurn() {
        depth -= 1
        guard depth == 0, !flushing else { return }
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
}

protocol CloseRequest: Sendable {
    var requestID: UUID { get }
    var quits: Bool { get }
    @MainActor func pages(in preparation: NativeClosePreparation) throws(NativeClosePreparation.Failure) -> [UUID]
}
extension PrepareToClosePages {
    var quits: Bool { false }
    @MainActor func pages(in preparation: NativeClosePreparation) throws(NativeClosePreparation.Failure) -> [UUID] {
        pageIDs
    }
}
extension PrepareToCloseWindows {
    var quits: Bool { false }
    @MainActor func pages(in preparation: NativeClosePreparation) throws(NativeClosePreparation.Failure) -> [UUID] {
        preparation.pagesForWindows(windowIDs)
    }
}
extension PrepareToQuit {
    var quits: Bool { true }
    @MainActor func pages(in preparation: NativeClosePreparation) throws(NativeClosePreparation.Failure) -> [UUID] {
        try preparation.allPagesForQuit()
    }
}
extension CrestCore {
    func send(_ answer: AnswerQuitWithDownloads) throws(NativeClosePreparation.Failure) { try closing.answer(answer) }
}
