import Foundation
import Observation

// MARK: - Types

struct BrowserCredentialSaveResult: Equatable, Sendable {
    let descriptor: CredentialDescriptor
    let disposition: BrowserCredentialSaveDisposition
}

struct BrowserCredentialSaveOperation {
    let id: UUID
    let completion: Task<Void, Never>
}

@Observable
@MainActor
final class BrowserStore {
    /// This window in the core's device, which owns what it shows.
    let windowID: UUID
    /// Advances each time this window shows another Space or tab by an
    /// intent of its own, or a tab moves into or out of it.
    private var windowRevision = 0
    /// The last move a Next or Previous Space command made in this window,
    /// which the Space pager follows around the ends of the Spaces.
    private(set) var spaceStep: BrowserSpaceStep?
    var localSyncErrorDescription: String?
    let browsingMode: BrowserBrowsingMode
    let tabMultiSelection = BrowserTabMultiSelection()
    let family: BrowserStoreFamily
    /// The process's core, which every window of every browsing mode shares.
    @ObservationIgnored let core: CrestCore
    @ObservationIgnored let credentialVault: any CredentialVault
    @ObservationIgnored var credentialSaveOperations: [BrowserCredentialSaveKey: BrowserCredentialSaveOperation] = [:]
    @ObservationIgnored let linkPreferences: BrowserLinkPreferenceStore
    @ObservationIgnored var pendingMovedTabActivation: BrowserTabRuntimeAssignment?
    @ObservationIgnored weak var interactionObserver: (any BrowserStoreInteractionObserving)?
    @ObservationIgnored weak var tabLinkProvider: (any BrowserTabLinkProviding)?
    @ObservationIgnored weak var tabCopying: (any BrowserTabCopying)?
    /// What this window showed when it last read the core, which it keeps
    /// showing once the core no longer has it open.
    @ObservationIgnored private var lastWindow: WindowState
    /// The Space this window showed when it last followed its session, under
    /// its profile and access policy then.
    @ObservationIgnored private var lastSelectionScope: BrowserSelectionScope
    /// Whether this window closed. The core can open another window under
    /// the identity it had, as the first window always reopens, so a closed
    /// store reads and answers to nothing by that identity.
    @ObservationIgnored private(set) var isClosed = false

    /// What the core says this window shows, or what it showed last once it
    /// closed.
    var window: WindowState {
        guard !isClosed, let shown = core.state.windows[windowID]?.value else { return lastWindow }
        lastWindow = shown
        return shown
    }

    /// Where this window stands in what it shows, for the readers that follow
    /// it as a whole, such as its page host: the revision the read model gives
    /// its workspace's session, and how many times the window itself showed
    /// something else.
    var sessionRevision: BrowserSessionRevision {
        BrowserSessionRevision(session: workspaceModel?.sessionRevision, window: windowRevision)
    }

    var selectedSpaceID: UUID { windowModel?.shownSpaceID ?? lastWindow.shownSpace }

    /// The tab this window shows in a Space, if any.
    func selectedTabID(in spaceID: UUID) -> UUID? {
        guard let windowModel else { return lastWindow.shownTabID(in: spaceID) }
        return windowModel.shownTabID(in: spaceID)
    }

    var isPrivateBrowsing: Bool { browsingMode.isPrivate }
    var isTemporaryWorkspace: Bool { temporarySourceAssignment != nil }
    var temporarySourceAssignment: BrowserSpaceRuntimeAssignment? { family.temporarySourceAssignment }

    /// Shows a Space in this window, on the tab it last showed there or the
    /// Space's fallback.
    func selectPresentedSpace(_ id: UUID) {
        guard !isDeleting(id), spaceModel(id) != nil else { return }
        guard sendWindowIntent(ShowSpace(windowID: windowID, spaceID: id)) else { return }
        tabMultiSelection.clear()
        windowRevision &+= 1
    }

    /// Shows the Space before or after this window's, wrapping, among the
    /// Spaces it may show, and answers it; nil when the core showed no other.
    @discardableResult
    func selectAdjacentSpace(_ direction: BrowserSpaceSwipeDirection) -> UUID? {
        let shown = selectedSpaceID
        guard sendWindowIntent(ShowAdjacentSpace(windowID: windowID, direction: direction.core)),
            selectedSpaceID != shown
        else { return nil }
        spaceStep = BrowserSpaceStep(origin: shown, destination: selectedSpaceID, direction: direction)
        tabMultiSelection.clear()
        windowRevision &+= 1
        return selectedSpaceID
    }

    /// Shows the tab one stop from this window's in the order its sidebar
    /// shows them, wrapping, and answers it; nil when the core showed no other.
    @discardableResult
    func selectAdjacentTab(_ direction: AdjacentDirection) -> UUID? {
        let shown = shownTab?.id
        guard sendWindowIntent(ShowAdjacentTab(windowID: windowID, direction: direction)),
            let next = shownTab?.id, next != shown
        else { return nil }
        windowRevision &+= 1
        return next
    }

    /// Shows the tab of this window's Space used most recently other than the
    /// one it shows, which the core chooses. False when there is none.
    @discardableResult
    func showMostRecentTab() -> Bool {
        let shown = shownTab?.id
        guard sendWindowIntent(ShowMostRecentTab(windowID: windowID)), shownTab?.id != shown else { return false }
        windowRevision &+= 1
        return true
    }

    func clearPresentedTabSelection(in spaceID: UUID) {
        guard sendWindowIntent(ShowTab(windowID: windowID, spaceID: spaceID, tabID: nil)) else {
            return
        }
        windowRevision &+= 1
    }

    /// Shows a tab in this window and records when it was last used, which
    /// current-tab cleanup reads. Answers false when the core would not show it.
    @discardableResult
    func activateSessionTab(_ id: UUID, in spaceID: UUID) -> Bool {
        guard !isDeleting(spaceID), spaceModel(spaceID)?.tabs.contains(id) == true,
            sendWindowIntent(ShowTab(windowID: windowID, spaceID: spaceID, tabID: id))
        else { return false }
        windowRevision &+= 1
        return true
    }

    /// Stops showing a tab the session keeps: the window returns to the tab it
    /// showed before in that Space, or shows nothing there.
    func dismissShownTab(_ id: UUID, in spaceID: UUID) {
        guard
            sendWindowIntent(
                DismissShownTab(windowID: windowID, spaceID: spaceID, tabID: id))
        else { return }
        windowRevision &+= 1
    }

    /// The column shares this window keeps for a split group it resized.
    func resizeSplitColumns(_ fractions: [Double], for groupID: UUID) {
        sendWindowIntent(ResizeSplitColumns(windowID: windowID, groupID: groupID, shares: fractions))
    }

    /// Runs one intent about this window. What it changed, including a tab
    /// use the core recorded, reaches the read model through the core's
    /// changes. Answers false when a rule refused it.
    @discardableResult
    private func sendWindowIntent(_ intent: some Intent) -> Bool {
        do { try core.send(intent) } catch { return false }
        lastSelectionScope = selectionScope
        return true
    }

    /// What this window shows changed without an intent of its own, as when a
    /// tab moved into or out of it.
    func showsAnew() {
        windowRevision &+= 1
    }

    /// A window over a new family the core opens from `seed`, whose tabs wear
    /// the images `images` holds for the seed's tabs. Without `spaceID` it
    /// opens on the launch Space and its fallback tab; with one it shows that
    /// Space and only the `tabs` named.
    convenience init(
        seed: SessionState.Seed,
        images: [UUID: Data] = [:],
        showing spaceID: UUID? = nil,
        tabs: [UUID: UUID] = [:],
        credentialVault: any CredentialVault = InMemoryCredentialVault(),
        browsingMode: BrowserBrowsingMode = .standard,
        linkPreferences: BrowserLinkPreferenceStore? = nil,
        core: CrestCore = CrestCore()
    ) {
        self.init(
            opening: BrowserWindowOpening(showingSpaceID: spaceID, showingTabs: tabs, restoresTabs: spaceID == nil),
            credentialVault: credentialVault,
            browsingMode: browsingMode,
            family: BrowserStoreFamily(seed: seed, images: images, browsingMode: browsingMode, core: core),
            linkPreferences: linkPreferences,
            core: core
        )
    }

    /// Opens a window over `family`'s session in `core`'s device as `opening`
    /// says.
    init(
        opening: BrowserWindowOpening = BrowserWindowOpening(),
        credentialVault: any CredentialVault,
        browsingMode: BrowserBrowsingMode,
        family: BrowserStoreFamily,
        linkPreferences: BrowserLinkPreferenceStore? = nil,
        core: CrestCore
    ) {
        windowID = opening.id
        self.linkPreferences = linkPreferences ?? BrowserLinkPreferenceStore(core: core)
        self.core = core
        self.credentialVault = credentialVault
        self.browsingMode = browsingMode
        self.family = family
        localSyncErrorDescription = nil
        lastWindow = WindowState(
            id: opening.id, workspaceID: UUID(), shownSpaceID: UUID(), shownTabs: [], splitColumnShares: [], cards: [],
            unavailableCommands: [])
        lastSelectionScope = BrowserSelectionScope(spaceID: lastWindow.shownSpace, space: nil)
        let workspace = family.register(self)
        do {
            try core.send(
                OpenWindow(
                    windowID: opening.id, workspaceID: workspace,
                    saved: opening.saved && family.keepsWindowRecords, copyingWindowID: opening.copying,
                    showingSpaceID: opening.showingSpaceID,
                    showingTabs: opening.showingTabs.map {
                        ShownTab(spaceID: $0.key, tabID: $0.value)
                    },
                    restoresTabs: opening.restoresTabs))
        } catch {
            preconditionFailure("The core refused to open a window over its own workspace: \(error)")
        }
        lastSelectionScope = selectionScope
    }

    /// Closes this window in the core's device. What it showed stays readable
    /// for anything still holding the store.
    func close() {
        guard !isClosed else { return }
        lastWindow = window
        isClosed = true
        _ = try? core.send(CloseWindow(windowID: windowID))
    }

    /// Whether this store is the open window the core names `windowID`, so a
    /// change the core addresses to that window is for it. A window opened
    /// again under the same identity is another window with a store of its
    /// own, so a closed store is none.
    func isOpen(as windowID: UUID) -> Bool {
        !isClosed && windowID == self.windowID
    }

    isolated deinit {
        close()
    }
}

// MARK: - Lifecycle

extension BrowserStore {
    func resetPrivateBrowsingSession() {
        guard isPrivateBrowsing else { return }
        credentialSaveOperations.removeAll()
        family.resetDeletionState()
        interactionObserver?.browserWillResetSession()
        guard
            family.send(
                ResetPrivateBrowsing(workspaceID: family.workspaceID, windowID: windowID), from: self,
                failure: "Core Space command failed")
        else { return }
        localSyncErrorDescription = nil
    }

    /// Another window over this family's session. Without a record of its own
    /// it starts as this window shows, unless `opening` names another.
    func makeWindowStore(_ opening: BrowserWindowOpening = BrowserWindowOpening()) -> BrowserStore {
        var opening = opening
        opening.copying = opening.copying ?? windowID
        let store = BrowserStore(
            opening: opening,
            credentialVault: credentialVault,
            browsingMode: browsingMode,
            family: family,
            linkPreferences: linkPreferences,
            core: core
        )
        store.localSyncErrorDescription = localSyncErrorDescription
        return store
    }
}

// MARK: - Persistence

extension BrowserStore {
    /// Returns once the sync stages the core queued for edits accepted before
    /// the call have finished and every such edit is on disk, or a save has
    /// failed. Quitting and backgrounding wait for it, off the main thread and
    /// never inside a block the main queue must finish first.
    func flushPendingSyncPersistence() async {
        await core.settleSync()
        await family.flushPendingSaves()
    }

    /// Flushes again after any pass the session changed during, so an edit
    /// still on its way when quitting or backgrounding began, such as a link
    /// being opened or a page's settling title, is saved and staged too.
    /// Callers bound the wait with `BrowserPersistenceFlush`.
    func flushPendingSyncPersistenceUntilSettled() async {
        var revision: BrowserSessionRevision
        repeat {
            revision = sessionRevision
            await flushPendingSyncPersistence()
        } while sessionRevision != revision
    }

    /// Brings what this window keeps of its own in line with the session it
    /// shows, each time `sessionRevision` moves; the window's root view calls
    /// it. The core's device has already moved or repaired this window. A
    /// window that now shows another Space, or its Space under another
    /// profile or policy, drops its multi-selection, and forgets a moved tab
    /// it was to show that it no longer shows.
    func followSession() {
        let scope = selectionScope
        if scope != lastSelectionScope {
            tabMultiSelection.clear()
        }
        if let activation = pendingMovedTabActivation,
            selectedSpaceID != activation.spaceID
                || selectedTabID(in: activation.spaceID) != activation.tabID
                || scope.profileID != activation.profileID
        {
            pendingMovedTabActivation = nil
        }
        lastSelectionScope = scope
    }

    /// The Space this window shows, under its profile and access policy now.
    private var selectionScope: BrowserSelectionScope {
        BrowserSelectionScope(spaceID: selectedSpaceID, space: spaceModel(selectedSpaceID))
    }
}
