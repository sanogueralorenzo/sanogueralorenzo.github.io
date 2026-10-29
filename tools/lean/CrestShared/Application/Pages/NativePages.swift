import Foundation

/// Owns logical pages and retained renderer/history state. Page facts reach
/// the session only as atomic records; WebKit commands precede page observers.
@MainActor
final class NativePages {
    enum Failure: Error, Equatable {
        case unknownPage(UUID)
        case duplicatePage(UUID)
        case windowNotOpen(UUID)
        case unknownWorkspace(UUID)
        case unknownSpace(UUID)
        case spaceBeingDeleted(UUID)
        case alreadyOwned(tab: UUID, page: UUID)
        case profileMismatch(page: UUID, space: UUID)
        case notLoadable(UUID)
        case stagedLinkElsewhere(page: UUID, source: UUID)
        case webKitNotRegistered
        case unsupportedAddress(String)
    }
    private struct TabKey: Hashable {
        let workspace: UUID
        let tab: UUID
    }
    private struct KeptHistory {
        let space: UUID
        let page: UUID?
        let history: NativePageHistory
    }
    private struct KeptState {
        let space: UUID
        let state: PageRestoreState
    }
    private struct Closing {
        let key: TabKey
        let space: UUID
    }
    private unowned let core: CrestCore
    private let now: @MainActor () -> Date
    private var open: [UUID: NativePage] = [:]
    private var order: [UUID] = []
    private var histories: [TabKey: KeptHistory] = [:]
    private var historyOrder: [TabKey] = []
    private var states: [TabKey: KeptState] = [:]
    private var stateOrder: [TabKey] = []
    private var keeping: [UUID: Closing] = [:]
    private var commands: [EngineCommand] = []
    private var delivering = false
    #if DEBUG
        var commandIssued: (@MainActor (EngineCommand) -> Void)?
    #endif
    private var receiving = false
    private var reports: [@MainActor () -> Void] = []
    init(core: CrestCore, now: @escaping @MainActor () -> Date = Date.init) {
        self.core = core
        self.now = now
    }
    var all: [NativePage] { order.compactMap { open[$0] } }
    func page(_ id: UUID) -> NativePage? { open[id] }
    @discardableResult
    func send(_ request: some NativePageRequest) throws -> [any CoreChange] {
        core.drain()
        var changes: [any CoreChange] = []
        switch request {
        case let request as OpenPage: try openPage(request, into: &changes)
        case let request as MovePage:
            let page = try known(request.pageID)
            _ = try window(request.windowID)
            let space = try hosting(request.workspaceID, request.spaceID)
            guard space.profileID == page.profileID else {
                throw Failure.profileMismatch(page: page.id, space: space.id)
            }
            try requireUnowned(request.workspaceID, request.windowID, request.tabID, moving: page.id)
            update(page, into: &changes) {
                page.move(workspace: request.workspaceID, space: space.id, tab: request.tabID, window: request.windowID)
            }
        case let request as ReleasePage:
            let page = try known(request.pageID)
            remove(page, into: &changes)
            if page.phase.holdsEnginePage { close(page, keepsState: request.keepsState) }
        case let request as Navigate: try load(request.pageID, request.input, held: false, into: &changes)
        case let request as LoadAddress: try load(request.pageID, request.url, held: true, into: &changes)
        case let request as LeavePageFailure:
            let page = try known(request.pageID)
            update(page, into: &changes) { page.leaveFailure() }
        case let request as StepHistory:
            let page = try known(request.pageID)
            if request.offset < 0, let failure = page.live.failure {
                update(page, into: &changes) { page.leaveFailure() }
                if !failure.replacedDocument { break }
            }
            if let entry = page.history.step(request.offset) { traverse(page, entry.id, into: &changes) }
        case let request as ShowHistoryEntry:
            let page = try known(request.pageID)
            if page.history.reaches(request.entryID) {
                update(page, into: &changes) { page.leaveFailure() }
                traverse(page, request.entryID, into: &changes)
            }
        case let request as RestoreTabHistory:
            let space = try hosting(request.workspaceID, request.spaceID)
            if core.state.workspaces[request.workspaceID]?.kind.isPrivate == false,
                let history = NativePageHistory.unarchive(request.archive)
            {
                let key = TabKey(workspace: request.workspaceID, tab: request.tabID)
                if histories[key] == nil
                    && !all.contains(where: { $0.workspaceID == key.workspace && $0.tabID == key.tab })
                {
                    remember(key, KeptHistory(space: space.id, page: nil, history: history))
                }
            }
        case let request as StageLink:
            let page = try known(request.pageID)
            let source = try known(request.sourcePageID)
            guard page.profileID == source.profileID && page.awaitsFirstLoad else {
                throw Failure.stagedLinkElsewhere(page: page.id, source: source.id)
            }
            commands.append(
                .stageNavigation(StageNavigation(pageID: page.id, stagedLinkID: request.stagedLinkID, url: request.url))
            )
        case let request as DiscardStagedLink:
            if open[request.sourcePageID] != nil {
                commands.append(.dropStagedLink(DropStagedLink(stagedLinkID: request.stagedLinkID)))
            }
        case let request as UnloadIdlePage:
            stamp(into: &changes)
            if let page = open[request.pageID], page.documents == request.documents,
                page.hiddenSince == request.hiddenSince,
                canAutomaticallyUnload(page)
            {
                unload(page, into: &changes)
            }
        case let request as ReportMemoryPressure:
            stamp(into: &changes)
            let candidates = all.filter { page in
                page.tabID != nil && page.phase == .live && page.hiddenSince != nil && page.live.url != nil
                    && !page.runsMedia
                    && held(page) != nil && !heldByAgent(page.tabID!)
            }.sorted {
                $0.hiddenSince == $1.hiddenSince
                    ? $0.id.uuidString < $1.id.uuidString : $0.hiddenSince! < $1.hiddenSince!
            }
            let limit: Int
            if core.platform == .desktop {
                limit = request.level == .critical ? max(1, (candidates.count + 1) / 2) : 1
            } else {
                limit = request.level == .critical ? 1 : 0
            }
            for page in candidates.prefix(limit) { unload(page, into: &changes) }
        default: preconditionFailure("Unhandled native page request: \(type(of: request))")
        }
        core.apply(changes)
        return changes
    }
    func report(_ event: some NativePageReport, from binding: WebKitEngineBinding) {
        guard core.engines.webKit === binding else { return }
        if delivering {
            reports.append { self.report(event, from: binding) }
            return
        }
        core.drain()
        var changes: [any CoreChange] = []
        if let offered = event as? PageOffered {
            adopt(offered, into: &changes)
        } else {
            if let closed = event as? PageClosed, let kept = keeping.removeValue(forKey: closed.pageID),
                let state = closed.restoreState
            {
                forgetState(kept.key)
                states[kept.key] = KeptState(space: kept.space, state: state)
                stateOrder.append(kept.key)
                while stateOrder.count > 64 { forgetState(stateOrder[0]) }
            }
            if let report = event as? any NativeDocumentReport, let page = open[report.pageID] {
                apply(event, to: page, into: &changes)
            }
        }
        core.apply(changes)
    }
    private func apply(_ event: some NativePageReport, to page: NativePage, into changes: inout [any CoreChange]) {
        switch event {
        case is PageCreated: update(page, into: &changes) { page.enter(.live) }
        case is PageCreationFailed: update(page, into: &changes) { page.enter(.failed) }
        case is PageClosed:
            if page.phase.holdsEnginePage {
                update(page, into: &changes) { page.enter(.closed) }
                closeOwner(page, into: &changes)
            }
        case is PageCloseRequested:
            if page.phase == .live && page.openedByPage { closeOwner(page, into: &changes) }
        case let report as NavigationCommitted:
            update(page, into: &changes) { page.commit(report.url, sameDocument: report.sameDocument) }
        case let report as NavigationFailed: update(page, into: &changes) { page.fail(report.failure) }
        case let report as PageStateChanged:
            update(page, into: &changes) { page.show(report.snapshot) }
            let at = now()
            if let title = page.retitle(at: at), page.tabID != nil || title.visit {
                record(
                    RecordPageTitle(
                        workspaceID: page.workspaceID, pageID: page.id, spaceID: page.spaceID, tabID: page.tabID,
                        url: title.url, title: title.title, at: at, visit: title.visit), into: &changes)
            }
            endPictureInPicture(page, shownAgain: false)
        case let report as NavigationFinished:
            let at = now()
            if page.finish(report.url, title: report.title, at: at) {
                record(
                    RecordPageNavigation(
                        workspaceID: page.workspaceID, pageID: page.id, spaceID: page.spaceID, tabID: page.tabID,
                        url: report.url, title: report.title, at: at, visitID: UUID(), hasIcon: page.icon != nil,
                        iconAccent: page.icon?.accent), into: &changes)
            }
        case let report as PageIconChanged:
            if page.showIcon(NativePageIcon(url: report.url, accent: report.accent)), let tab = page.tabID {
                record(
                    RecordPageIcon(
                        workspaceID: page.workspaceID, pageID: page.id, spaceID: page.spaceID, tabID: tab,
                        url: report.url, accent: report.accent, at: now()), into: &changes)
            }
        case let report as PageHistoryReported:
            var arrival: UUID?
            update(page, into: &changes) { arrival = page.history.report(report.entries, report.current) }
            if let arrival { commands.append(.goToHistoryEntry(GoToHistoryEntry(pageID: page.id, entryID: arrival))) }
        case let report as PageCrashed:
            if page.phase == .live {
                var recovers = false
                update(page, into: &changes) {
                    recovers = page.crash(isShown: isShown(page), domain: report.domain, code: report.code)
                }
                if recovers { commands.append(.recoverPage(RecoverPage(pageID: page.id))) }
            }
        case is StagedLinkUnavailable: update(page, into: &changes) { page.cancelLoad() }
        case is PictureInPictureReturned: returnPictureInPicture(page, into: &changes)
        case is NavigationStarted: break
        default: preconditionFailure("Unhandled native page report: \(type(of: event))")
        }
    }
    private func openPage(_ request: OpenPage, into changes: inout [any CoreChange]) throws {
        guard open[request.pageID] == nil else { throw Failure.duplicatePage(request.pageID) }
        let space = try hosting(request.workspaceID, request.spaceID)
        _ = try window(request.windowID)
        try requireUnowned(request.workspaceID, request.windowID, request.tabID, moving: nil)
        let opener = request.openerPageID.flatMap { open[$0] }.flatMap {
            $0.workspaceID == request.workspaceID && $0.profileID == space.profileID ? $0 : nil
        }
        guard core.engines.webKit != nil else { throw Failure.webKitNotRegistered }
        let page = NativePage(
            id: request.pageID, profileID: space.profileID, workspaceID: request.workspaceID, spaceID: space.id,
            tabID: request.tabID, windowID: request.windowID, transient: request.transient, openedByPage: opener != nil)
        open[page.id] = page
        order.append(page.id)
        var restore: PageRestoreState?
        if let tab = page.tabID {
            let key = TabKey(workspace: page.workspaceID, tab: tab)
            if let kept = states[key] {
                forgetState(key)
                if kept.space == space.id, let url = space.tabs.model(tab)?.url,
                    PageAddress.samePage(url, kept.state.url)
                {
                    restore = kept.state
                    page.restoring(kept.state.url)
                }
            }
            if opener == nil, let kept = histories[key] {
                forgetHistory(key)
                if kept.space == space.id, let shown = kept.history.shown, let url = space.tabs.model(tab)?.url,
                    PageAddress.samePage(url, shown.url)
                {
                    page.resume(kept.history, restores: restore != nil || kept.page == nil)
                }
            }
        }
        changes.append(PageOpened(page: page.state))
        commands.append(
            .createPage(
                CreatePage(
                    pageID: page.id, profileID: page.profileID,
                    isPrivate: core.state.workspaces[page.workspaceID]?.kind.isPrivate == true, windowID: page.windowID,
                    restoreState: restore)))
    }
    private func load(_ id: UUID, _ input: String, held: Bool, into changes: inout [any CoreChange]) throws {
        let page = try known(id)
        guard page.phase.holdsEnginePage else { throw Failure.notLoadable(id) }
        _ = try hosting(page.workspaceID, page.spaceID)
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let url: String
        if value == "about:blank" || value.hasPrefix("about:blank#") {
            url = value
        } else if held, let address = PageAddress.held(value) {
            url = address
        } else {
            let resolution = try core.query(ResolveAddress(workspaceID: page.workspaceID, spaceID: nil, input: input))
            guard let address = resolution.url else { throw Failure.unsupportedAddress(input) }
            url = address
        }
        update(page, into: &changes) { page.load(url) }
        commands.append(.loadPage(LoadPage(pageID: page.id, url: url, entryID: nil)))
    }
    private func traverse(_ page: NativePage, _ entry: UUID, into changes: inout [any CoreChange]) {
        guard page.phase == .live else { return }
        if page.history.holds(entry) {
            page.history.go(entry)
            commands.append(.goToHistoryEntry(GoToHistoryEntry(pageID: page.id, entryID: entry)))
        } else if page.history.reaches(entry) {
            var loaded: PageHistoryEntry?
            update(page, into: &changes) { loaded = page.history.load(entry) }
            if let loaded { commands.append(.loadPage(LoadPage(pageID: page.id, url: loaded.url, entryID: loaded.id))) }
        }
    }
    private func record(_ intent: some Intent, into changes: inout [any CoreChange]) {
        if let recorded = try? core.dispatch(intent) { changes.append(contentsOf: recorded) }
    }
    private func update(_ page: NativePage, into changes: inout [any CoreChange], _ edit: () -> Void) {
        let before = page.state
        edit()
        if page.state != before { changes.append(PageChanged(page: page.state)) }
    }
    private func remove(_ page: NativePage, into changes: inout [any CoreChange]) {
        open[page.id] = nil
        order.removeAll { $0 == page.id }
        changes.append(PageRemoved(pageID: page.id))
    }
    private func close(_ page: NativePage, keepsState: Bool) {
        if keepsState, let tab = page.tabID {
            let key = TabKey(workspace: page.workspaceID, tab: tab)
            keeping[page.id] = Closing(key: key, space: page.spaceID)
            forgetHistory(key)
            if page.history.shown != nil {
                remember(key, KeptHistory(space: page.spaceID, page: page.id, history: page.history))
            }
        }
        commands.append(.closePage(ClosePage(pageID: page.id, keepsState: keepsState)))
    }
    private func unload(_ page: NativePage, into changes: inout [any CoreChange]) {
        remove(page, into: &changes)
        changes.append(PageUnloaded(pageID: page.id, workspaceID: page.workspaceID, tabID: page.tabID!))
        close(page, keepsState: true)
    }
    private func closeOwner(_ page: NativePage, into changes: inout [any CoreChange]) {
        guard core.state.workspaces[page.workspaceID] != nil else { return }
        if page.tabID == nil {
            if (try? hosting(page.workspaceID, page.spaceID)) != nil {
                changes.append(TransientPageClosed(pageID: page.id, workspaceID: page.workspaceID))
            }
        } else if let tab = held(page) {
            record(
                CloseTab(workspaceID: page.workspaceID, windowID: page.windowID, spaceID: page.spaceID, tabID: tab.id),
                into: &changes)
        }
    }
    private func adopt(_ offer: PageOffered, into changes: inout [any CoreChange]) {
        let source = offer.sourcePageID.flatMap { open[$0] }.flatMap { $0.profileID == offer.profileID ? $0 : nil }
        let context: (workspace: UUID, window: UUID, space: UUID, after: UUID?)?
        if let source {
            context = (source.workspaceID, source.windowID, source.spaceID, source.tabID)
        } else if let id = offer.windowID, let window = core.state.windows[id] {
            let space = offer.spaceID ?? window.shownSpaceID
            context = (window.workspaceID, id, space, window.shownTabs.first { $0.spaceID == space }?.tabID)
        } else {
            context = nil
        }
        guard let context, let space = try? hosting(context.workspace, context.space),
            space.profileID == offer.profileID
        else {
            commands.append(.rejectOfferedPage(RejectOfferedPage(offerID: offer.offerID)))
            return
        }
        let tab = UUID()
        do {
            changes.append(
                contentsOf: try core.dispatch(
                    OpenTab(
                        workspaceID: context.workspace, windowID: context.window,
                        spaceID: space.id, tabID: tab, content: TabContent(address: offer.url, view: nil, title: nil),
                        placement: .current,
                        afterTabID: context.after, shows: offer.foreground)))
        } catch {
            commands.append(.rejectOfferedPage(RejectOfferedPage(offerID: offer.offerID)))
            return
        }
        let page = NativePage(
            id: UUID(), profileID: space.profileID, workspaceID: context.workspace, spaceID: space.id,
            tabID: tab, windowID: context.window, transient: nil, openedByPage: true)
        open[page.id] = page
        order.append(page.id)
        changes.append(PageOpened(page: page.state))
        changes.append(
            OfferedPageAdopted(
                pageID: page.id, workspaceID: page.workspaceID, windowID: page.windowID, spaceID: page.spaceID,
                tabID: tab, shows: offer.foreground))
        commands.append(
            .adoptOfferedPage(
                AdoptOfferedPage(
                    pageID: page.id, offerID: offer.offerID, profileID: page.profileID,
                    isPrivate: core.state.workspaces[page.workspaceID]?.kind.isPrivate == true, windowID: page.windowID)
            ))
    }
    private func returnPictureInPicture(_ page: NativePage, into changes: inout [any CoreChange]) {
        guard let tab = held(page), (try? hosting(page.workspaceID, page.spaceID)) != nil else { return }
        let windows = core.state.windows.values.filter { $0.workspaceID == page.workspaceID }
        guard
            let window = windows.first(where: { $0.id == page.windowID }) ?? windows.first(where: {
                $0.shownSpaceID == page.spaceID
            }) ?? windows.first
        else { return }
        record(ShowTab(windowID: window.id, spaceID: page.spaceID, tabID: tab.id), into: &changes)
        page.seen(true, at: now())
        changes.append(WindowBroughtForward(windowID: window.id))
    }
    /// Release physical pages before workspace removal reaches UI observers.
    func prepare(_ changes: [any CoreChange]) -> [any CoreChange] {
        let closed = Set(
            changes.compactMap { change -> UUID? in
                if let closed = change as? WorkspaceClosed { return closed.workspaceID }
                if let wire = change as? Change, case .workspaceClosed(let closed) = wire { return closed.workspaceID }
                return nil
            })
        var removed: [any CoreChange] = []
        for page in all where closed.contains(page.workspaceID) {
            remove(page, into: &removed)
            if page.phase.holdsEnginePage { commands.append(.closePage(ClosePage(pageID: page.id, keepsState: false))) }
        }
        return removed
    }
    /// Commands may report synchronously. Those reports follow the batch that
    /// caused them, after handovers, unloads and session observers complete.
    func flushReports() {
        guard !delivering && !receiving else { return }
        receiving = true
        defer { receiving = false }
        var index = 0
        while index < reports.count {
            let report = reports[index]
            index += 1
            report()
        }
        reports.removeAll(keepingCapacity: true)
    }
    func reconcile(in batch: inout CoreChangeBatch) {
        var changes: [any CoreChange] = []
        for page in all where core.state.workspaces[page.workspaceID] == nil {
            remove(page, into: &changes)
            if page.phase.holdsEnginePage { commands.append(.closePage(ClosePage(pageID: page.id, keepsState: false))) }
        }
        for key in Array(states.keys) where held(key, states[key]!.space) == nil { forgetState(key) }
        for key in Array(histories.keys) where held(key, histories[key]!.space) == nil { forgetHistory(key) }
        stamp(into: &changes)
        for change in changes { change.apply(to: core, in: &batch) }
    }
    private func stamp(into changes: inout [any CoreChange]) {
        let at = now()
        for page in all {
            let shownAgain = page.tabID.map { _ in page.seen(isShown(page), at: at) } ?? false
            endPictureInPicture(page, shownAgain: shownAgain)
            if page.recoversWhenShown && page.phase == .live && isShown(page) {
                var recovers = false
                update(page, into: &changes) { recovers = page.recover() }
                if recovers { commands.append(.recoverPage(RecoverPage(pageID: page.id))) }
            }
        }
    }
    private func endPictureInPicture(_ page: NativePage, shownAgain: Bool) {
        if page.showsPictureInPicture && (shownAgain || (try? hosting(page.workspaceID, page.spaceID)) == nil) {
            commands.append(.exitPictureInPicture(ExitPictureInPicture(pageID: page.id)))
        }
    }
    func flushCommands() {
        guard !delivering else { return }
        delivering = true
        defer { delivering = false }
        var index = 0
        while index < commands.count {
            let command = commands[index]
            index += 1
            #if DEBUG
                commandIssued?(command)
            #endif
            core.engines.run(command)
        }
        commands.removeAll(keepingCapacity: true)
    }
    func canAutomaticallyUnload(_ page: NativePage) -> Bool {
        page.tabID != nil && page.phase == .live && page.hiddenSince.map { now().timeIntervalSince($0) >= 300 } == true
            && page.live.url != nil && !page.live.isLoading && !page.runsMedia && held(page) != nil
            && !heldByAgent(page.tabID!) && !isShown(page)
    }
    func idlePages() -> [IdlePageCandidate] {
        all.filter(canAutomaticallyUnload).map {
            IdlePageCandidate(pageID: $0.id, documents: $0.documents, hiddenSince: $0.hiddenSince!)
        }
    }
    func archivedHistory(_ id: UUID) -> Data? {
        let kept = histories.first { $0.value.page == id }
        let workspace = open[id]?.workspaceID ?? kept?.key.workspace
        let history = open[id]?.history ?? kept?.value.history
        guard let workspace, core.state.workspaces[workspace]?.kind.isPrivate == false else { return nil }
        return history?.archive()
    }
    func showing(workspace: UUID, window: UUID, tab: UUID) -> PageLiveState? {
        let pages = all.filter { $0.workspaceID == workspace && $0.tabID == tab && $0.phase.holdsEnginePage }
        return (pages.first { $0.windowID == window } ?? pages.first)?.live
    }
    func appearances(workspace: UUID, window: UUID) -> [TabPageAppearance] {
        var kept: [UUID: NativePage] = [:]
        var order: [UUID] = []
        for page in all where page.workspaceID == workspace && page.phase.holdsEnginePage {
            guard let tab = page.tabID else { continue }
            if kept[tab] == nil { order.append(tab) }
            if kept[tab] == nil || page.windowID == window { kept[tab] = page }
        }
        return order.compactMap { tab in
            kept[tab].map { TabPageAppearance(tabID: tab, address: $0.live.address, title: $0.live.title) }
        }
    }
    private func heldByAgent(_ tab: UUID) -> Bool { core.state.agentSessions.contains { $0.tabIDs.contains(tab) } }
    private func isShown(_ page: NativePage) -> Bool {
        guard let tab = page.tabID else { return true }
        return core.state.windows.values.contains { window in
            window.workspaceID == page.workspaceID && window.shownSpaceID == page.spaceID
                && window.cards.contains { $0.spaceID == page.spaceID && $0.tabIDs.contains(tab) }
        }
    }
    private func known(_ id: UUID) throws -> NativePage {
        guard let page = open[id] else { throw Failure.unknownPage(id) }
        return page
    }
    private func window(_ id: UUID) throws -> WindowStateModel {
        guard let window = core.state.windows[id] else { throw Failure.windowNotOpen(id) }
        return window
    }
    private func hosting(_ workspace: UUID, _ space: UUID) throws -> SpaceModel {
        guard let owner = core.state.workspaces[workspace] else { throw Failure.unknownWorkspace(workspace) }
        guard let model = owner.spaces.model(space) else { throw Failure.unknownSpace(space) }
        let deletions =
            owner.kind.ownsSpaces ? owner.spaceDeletions : core.state.workspaces.values.flatMap(\.spaceDeletions)
        guard !deletions.contains(where: { $0.spaceID == space && $0.profileID == model.profileID }) else {
            throw Failure.spaceBeingDeleted(space)
        }
        return model
    }
    private func held(_ key: TabKey, _ space: UUID) -> TabStateModel? {
        (try? hosting(key.workspace, space))?.tabs.model(key.tab)
    }
    private func held(_ page: NativePage) -> TabStateModel? {
        page.tabID.flatMap { held(TabKey(workspace: page.workspaceID, tab: $0), page.spaceID) }
    }
    private func requireUnowned(_ workspace: UUID, _ window: UUID, _ tab: UUID?, moving: UUID?) throws {
        if let tab,
            let owner = all.first(where: {
                $0.id != moving && $0.workspaceID == workspace && $0.windowID == window && $0.tabID == tab
            })
        {
            throw Failure.alreadyOwned(tab: tab, page: owner.id)
        }
    }
    private func remember(_ key: TabKey, _ kept: KeptHistory) {
        histories[key] = kept
        historyOrder.append(key)
        while historyOrder.count > 64 { forgetHistory(historyOrder[0]) }
    }
    private func forgetHistory(_ key: TabKey) {
        histories[key] = nil
        historyOrder.removeAll { $0 == key }
    }
    private func forgetState(_ key: TabKey) {
        states[key] = nil
        stateOrder.removeAll { $0 == key }
    }
}
