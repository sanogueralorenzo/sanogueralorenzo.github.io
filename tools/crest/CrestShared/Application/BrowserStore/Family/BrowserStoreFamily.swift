import Foundation
import Observation

@Observable
@MainActor
final class BrowserStoreFamily {
    private struct WeakStore {
        weak var value: BrowserStore?
    }

    private var stores: [WeakStore] = []
    private let core: BrowserCoreSessionAuthority
    let temporarySourceAssignment: BrowserSpaceRuntimeAssignment?
    let temporarySettingsBrowser: BrowserStore?
    /// The Space deletions this family is running now, until each attempt
    /// ends, whether it finished the deletion or failed.
    private(set) var activeSpaceDeletions: Set<UUID> = []
    /// The Spaces this device began deleting before the core records it. A
    /// borrowed workspace's windows read its source's deletions too: a Space's
    /// profile and privacy always read through to the workspace that lends it,
    /// including while it goes.
    var locallyDeletingSpaceIDs: Set<UUID> {
        activeSpaceDeletions.union(temporarySettingsBrowser?.deletingSpaceIDs ?? [])
    }
    @ObservationIgnored private weak var spaceDataDeleter: (any BrowserSpaceDataDeleting)?
    @ObservationIgnored private weak var spaceCleanupStore: BrowserStore?
    @ObservationIgnored private(set) var spaceCleanupTask: Task<Void, Never>?
    @ObservationIgnored weak var pageDismissalAuthorizer: (any BrowserPageDismissalAuthorizing)?
    /// The core that keeps this family's session in its file; nil in memory.
    @ObservationIgnored private let storage: CrestCore?

    /// Whether this family's windows keep their records across launches:
    /// only the windows over the session the core keeps in its file do.
    var keepsWindowRecords: Bool { storage != nil }

    /// Whether the core still holds this family's workspace open. A borrowed
    /// one closes once its owner no longer lends its Space.
    var isOpen: Bool { core.isOpen }

    /// A family over a workspace `crest` opens in memory from `seed`, of the
    /// kind `browsingMode` browses in, whose tabs wear the images `images`
    /// holds for the seed's tabs. It keeps nothing: it is never saved or synced.
    convenience init(
        seed: SessionState.Seed, images: [UUID: Data] = [:], browsingMode: BrowserBrowsingMode = .standard,
        core crest: CrestCore
    ) {
        let kind: WorkspaceKind = browsingMode.isPrivate ? .private : .persistent
        do {
            self.init(memory: try BrowserCoreSessionAuthority.open(kind, seed: seed, images: images, in: crest))
        } catch {
            preconditionFailure("The core refused to open a workspace over a session it was given: \(error)")
        }
    }

    /// A family over a new private workspace in `crest`, which starts from the
    /// core's private template.
    convenience init(privateIn crest: CrestCore) {
        self.init(startingAs: .private, in: crest)
    }

    /// A family over a new workspace of `kind` in `crest`, which starts from
    /// the core's template for it and keeps nothing.
    convenience init(startingAs kind: WorkspaceKind, in crest: CrestCore) {
        do {
            self.init(memory: try BrowserCoreSessionAuthority.open(kind, seed: nil, in: crest))
        } catch {
            preconditionFailure("The core refused to open a \(kind.name) workspace: \(error)")
        }
    }

    private init(memory core: BrowserCoreSessionAuthority) {
        self.core = core
        temporarySourceAssignment = nil
        temporarySettingsBrowser = nil
        storage = nil
        followCloudDeliveries()
    }

    /// The family of the session `storage` keeps in its file, opened by
    /// `stored`. The read model keeps the image each open tab of the session
    /// wears in `favicons` from now on, following each batch that changes the
    /// session, and prunes the images of tabs it does not hold open.
    init(stored: BrowserCoreSessionAuthority, storage: CrestCore, favicons: any BrowserFaviconStoring) {
        core = stored
        temporarySourceAssignment = nil
        temporarySettingsBrowser = nil
        self.storage = storage
        if let workspace { storage.state.favicons.keep(workspace, in: favicons) }
        storage.storageFailureHandler = { [weak self] reason in self?.storageDidFail(reason) }
        followCloudDeliveries()
    }

    private init(
        core: BrowserCoreSessionAuthority, assignment: BrowserSpaceRuntimeAssignment, settingsBrowser: BrowserStore
    ) {
        self.core = core
        temporarySourceAssignment = assignment
        temporarySettingsBrowser = settingsBrowser
        storage = nil
        followCloudDeliveries()
    }

    /// A family over a workspace that borrows the Space `assignment` names
    /// from this family's workspace, whose settings `settingsBrowser` edits.
    func makeBorrowed(in assignment: BrowserSpaceRuntimeAssignment, settingsBrowser: BrowserStore) throws
        -> BrowserStoreFamily
    {
        BrowserStoreFamily(
            core: try core.borrow(assignment),
            assignment: assignment, settingsBrowser: settingsBrowser)
    }

    /// Closes this family's workspace, and first every workspace that borrows
    /// from it. Its windows close in the core, which keeps their saved
    /// records. Closing it again does nothing.
    func close() {
        core.close()
    }

    /// Composition supplies the engine adapter once. Sync schedules it only
    /// after the core intent and accepted journal have committed together.
    func configureSpaceDataCleanup(_ dataDeleter: any BrowserSpaceDataDeleting, from store: BrowserStore) {
        spaceDataDeleter = dataDeleter
        spaceCleanupStore = store
        scheduleSpaceDataCleanup()
    }

    private func scheduleSpaceDataCleanup() {
        guard spaceCleanupTask == nil, !(workspace?.spaceDeletions ?? []).isEmpty,
            let dataDeleter = spaceDataDeleter, let store = spaceCleanupStore
        else { return }
        spaceCleanupTask = Task { [weak self] in
            await store.resumePendingSpaceDeletions(dataDeleter: dataDeleter)
            self?.spaceCleanupTask = nil
        }
    }

    /// The workspace the core gave this family's session.
    var workspaceID: UUID { core.workspaceID }

    /// This family's workspace in the read model, or nil once the core
    /// closed it.
    var workspace: WorkspaceModel? { core.device?.state.workspaces[workspaceID] }

    /// Adds a window of this family, and answers the workspace it shows. A
    /// session shows in the windows of the one core that opened it.
    func register(_ store: BrowserStore) -> UUID {
        guard core.device === store.core else {
            preconditionFailure("A session shows in the windows of the core that opened it.")
        }
        stores.removeAll { $0.value == nil }
        stores.append(WeakStore(value: store))
        return core.workspaceID
    }

    /// Runs one session intent that `source`'s window issued. What it changed
    /// reaches the read model through the core's changes, which every window
    /// reads. Answers whether the session changed; a refusal changes nothing,
    /// and the window's sync status reports it after `failure`.
    @discardableResult
    func send(
        _ intent: some Intent, from source: BrowserStore, offering image: Data? = nil,
        failure: String = "Core command failed"
    ) -> Bool {
        perform(intent, from: source, offering: image, failure: failure)?.changed ?? false
    }

    /// Runs one session intent as `send` does, and answers the changes the
    /// core published with it and whether the session changed, or nil when a
    /// rule refused it. `image` is the image `source` holds for the tab the
    /// core tells to adopt its issuer's, such as a favicon pulled from a page.
    func perform(
        _ intent: some Intent, from source: BrowserStore, offering image: Data? = nil,
        failure: String = "Core command failed"
    ) -> (changes: [Change], changed: Bool)? {
        let before = workspace?.sessionRevision
        let changes: [Change]
        let favicons = source.core.state.favicons
        if let image { favicons.offer(FaviconAssets.Offer(assigned: image), in: workspaceID) }
        defer { if image != nil { favicons.withdrawOffer(in: workspaceID) } }
        do {
            changes = try source.core.send(intent)
        } catch {
            source.localSyncErrorDescription = "\(failure): \(error)"
            return nil
        }
        return (changes, workspace?.sessionRevision != before)
    }

    /// Runs one session intent as `send` does, and answers the changes the
    /// core published with it, or throws the rule that refused it or the save
    /// that failed, for a caller that handles either, such as a deletion step
    /// the core saves before it returns.
    @discardableResult
    func commit(_ intent: some Intent, from source: BrowserStore) throws(Rejection) -> [Change] {
        try source.core.send(intent)
    }

    /// Whether the core would accept a session intent `source`'s window
    /// issues, asked without changing anything. This is how menus ask the
    /// core's rules, such as a folder's depth or a split's size, instead of
    /// keeping copies of them.
    func canSend(_ intent: some Intent, from source: BrowserStore) -> Bool {
        guard let permission = try? source.core.query(CanSend(intent: intent)) else { return false }
        return permission.refusal == nil
    }

    /// The rule that would refuse a session intent `source`'s window issues,
    /// asked without changing anything, or nil when the core would accept it
    /// or could not answer.
    func refusal(of intent: some Intent, from source: BrowserStore) -> Rejection? {
        (try? source.core.query(CanSend(intent: intent)))?.refusal
    }

    /// Moves a tab from `source`'s window to `destination`'s. The core changes
    /// both workspaces together, saving the one that keeps a file with its
    /// journal before it returns, and both windows follow what they show now,
    /// even when only that changed.
    static func moveTab(
        _ intent: MoveTabToWindow, from source: BrowserStore, to destination: BrowserStore
    ) throws(Rejection) {
        try source.core.send(intent)
        source.showsAnew()
        destination.showsAnew()
    }

    // MARK: - Actions - Storage

    /// Returns once every edit this family has accepted is on disk, or once a
    /// save has failed. A family in memory has nothing to wait for.
    func flushPendingSaves() async {
        await storage?.flushPendingSaves()
    }

    /// A save the core started itself failed: every window shows it the way
    /// a failed local save always has, through the sync status.
    private func storageDidFail(_ reason: StorageFailure) {
        stores.removeAll { $0.value == nil }
        for store in stores.compactMap(\.value) {
            store.localSyncErrorDescription = CoreState.description(of: reason)
        }
    }

    /// Each time the cloud transport's records commit, a Space deletion whose
    /// cleanup has not finished, such as one the cloud began, starts it again.
    private func followCloudDeliveries() {
        core.device?.followCloudDeliveries(self) { [weak self] in self?.scheduleSpaceDataCleanup() }
    }

    func beginDeletingSpace(_ id: UUID) -> Bool {
        activeSpaceDeletions.insert(id).inserted
    }

    func isActivelyDeletingSpace(_ id: UUID) -> Bool { activeSpaceDeletions.contains(id) }

    func finishDeletingSpace(_ id: UUID) {
        activeSpaceDeletions.remove(id)
    }

    func resetDeletionState() {
        activeSpaceDeletions.removeAll()
    }
}
