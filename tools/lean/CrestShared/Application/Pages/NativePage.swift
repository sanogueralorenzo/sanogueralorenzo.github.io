import Foundation

struct NativePageIcon: Equatable {
    let url: String
    let accent: TabIconAccent?
}

/// A logical page’s process-local state. WebKit owns the renderer; this owner
/// keeps document identity, recording limits, recovery budget and residency.
final class NativePage {
    let id: UUID
    let profileID: UUID
    private(set) var workspaceID: UUID
    private(set) var spaceID: UUID
    private(set) var tabID: UUID?
    private(set) var windowID: UUID
    let transient: TransientPresentation?
    let openedByPage: Bool
    private(set) var phase = PagePhase.opening
    private(set) var documents: Int64 = 0
    private(set) var history = NativePageHistory()
    private(set) var icon: NativePageIcon?
    private var shown = PageSnapshot.blank
    private var failure: PageFailure?
    private(set) var documentAddress: String?
    private var isRecorded = false
    private var record: (title: String, at: Date, visitTitles: Int)?
    private(set) var hiddenSince: Date?
    private var crashes = 0
    private var stoppedUnseen: (domain: String, code: Int64)?

    init(
        id: UUID, profileID: UUID, workspaceID: UUID, spaceID: UUID, tabID: UUID?, windowID: UUID,
        transient: TransientPresentation?, openedByPage: Bool = false
    ) {
        self.id = id
        self.profileID = profileID
        self.workspaceID = workspaceID
        self.spaceID = spaceID
        self.tabID = tabID
        self.windowID = windowID
        self.transient = transient
        self.openedByPage = openedByPage
    }
    var state: PageState {
        PageState(
            id: id, workspaceID: workspaceID, spaceID: spaceID, tabID: tabID, phase: phase, live: live,
            windowID: windowID, documents: documents)
    }
    var live: PageLiveState {
        PageLiveState(
            url: shown.url, pendingURL: shown.pendingURL, title: shown.title, isLoading: shown.isLoading,
            canGoBack: history.canGoBack || failure?.replacedDocument == false && shown.url != nil,
            canGoForward: history.canGoForward, security: shown.security, failure: failure, media: shown.media,
            address: failure?.url ?? shown.pendingURL ?? shown.url)
    }
    var awaitsFirstLoad: Bool {
        phase == .opening || phase == .live && documentAddress == nil && shown.url == nil && shown.pendingURL == nil
    }
    var showsPictureInPicture: Bool { phase == .live && shown.media.contains(.pictureInPicture) }
    var runsMedia: Bool { phase == .live && !shown.media.isEmpty }
    var recoversWhenShown: Bool { stoppedUnseen != nil }
    @discardableResult
    func enter(_ next: PagePhase) -> Bool {
        let follows = next == .live || next == .failed ? phase == .opening : next == .closed && phase.holdsEnginePage
        guard follows else { return false }
        phase = next
        return true
    }
    func move(workspace: UUID, space: UUID, tab: UUID?, window: UUID) {
        workspaceID = workspace
        spaceID = space
        tabID = tab
        windowID = window
    }
    func commit(_ url: String, sameDocument: Bool) {
        if !sameDocument {
            failure = nil
            stoppedUnseen = nil
            documents += 1
        }
        if sameDocument, let previous = documentAddress, PageAddress.samePage(previous, url) { return }
        documentAddress = url
        isRecorded = false
        record = nil
        if !sameDocument { icon = nil }
    }
    @discardableResult
    func finish(_ url: String, title: String, at now: Date) -> Bool {
        crashes = 0
        guard !isRecorded else { return false }
        documentAddress = url
        isRecorded = true
        record = (title, now, 0)
        return true
    }
    func retitle(at now: Date) -> (url: String, title: String, visit: Bool)? {
        guard let recorded = record, let url = documentAddress, !shown.title.isEmpty,
            Data(shown.title.utf8) != Data(recorded.title.utf8), let address = shown.url,
            PageAddress.samePage(address, url)
        else { return nil }
        let visit = recorded.title.isEmpty || now.timeIntervalSince(recorded.at) <= 5 && recorded.visitTitles < 5
        record = (shown.title, recorded.at, visit ? recorded.visitTitles + 1 : recorded.visitTitles)
        return (url, shown.title, visit)
    }
    func fail(_ reason: PageFailure) {
        isRecorded = true
        record = nil
        failure = reason
        pending(nil)
    }
    func load(_ url: String) {
        failure = nil
        crashes = 0
        stoppedUnseen = nil
        pending(url)
    }
    func cancelLoad() { pending(nil, isLoading: false) }
    func leaveFailure() { failure = nil }
    func restoring(_ url: String) { pending(url) }
    func resume(_ history: NativePageHistory, restores: Bool) {
        self.history = history
        history.reopen(restores: restores)
    }
    @discardableResult
    func seen(_ isShown: Bool, at now: Date) -> Bool {
        let returned = isShown && hiddenSince != nil
        hiddenSince = isShown ? nil : hiddenSince ?? now
        return returned
    }
    func show(_ snapshot: PageSnapshot) { shown = snapshot }
    @discardableResult
    func showIcon(_ icon: NativePageIcon) -> Bool {
        self.icon = icon
        return tabID != nil && isRecorded
    }
    func crash(isShown: Bool, domain: String, code: Int64) -> Bool {
        if isShown { return stopped(domain, code) }
        stoppedUnseen = (domain, code)
        pending(nil, isLoading: false)
        return false
    }
    func recover() -> Bool {
        guard let reason = stoppedUnseen else { return false }
        stoppedUnseen = nil
        return stopped(reason.domain, reason.code)
    }
    private func stopped(_ domain: String, _ code: Int64) -> Bool {
        crashes += 1
        if crashes <= 2 { return true }
        failure = PageFailure(
            error: .webContentProcessStopped, url: shown.url, replacedDocument: true, domain: domain, code: code)
        pending(nil, isLoading: false)
        return false
    }
    private func pending(_ url: String?, isLoading: Bool? = nil) {
        shown = PageSnapshot(
            url: shown.url, pendingURL: url, title: shown.title, isLoading: isLoading ?? shown.isLoading,
            security: shown.security, media: shown.media)
    }
}
