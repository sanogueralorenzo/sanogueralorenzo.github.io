import Foundation
import Observation

/// A workspace attached to this device, as the read model keeps it: what kind
/// of session it is, its own members and its Spaces in order. Each Space is an
/// object of its own, so a change inside one Space never notifies the readers
/// of the Space list. Each of its own values is stored before it is
/// announced; see `BrowserStoreFirstObservable`.
///
/// The workspace also announces its session as a whole: `sessionRevision`
/// advances once for each batch of the core's changes that changed any of
/// it, for the few readers that follow the whole session, such as a window's
/// page host bringing its pages in line.
@MainActor
@Observable
final class WorkspaceModel: Identifiable {
    // MARK: - Variables

    let id: UUID
    let kind: WorkspaceKind
    let spaces: ObservedList<SpaceModel>
    /// Space deletions under way on this device.
    private(set) var spaceDeletions: [SpaceDeletionState] {
        get { observed(\.spaceDeletionsStorage, as: \.spaceDeletions) }
        set { publish(newValue, into: \.spaceDeletionsStorage, as: \.spaceDeletions) }
    }
    @ObservationIgnored private var spaceDeletionsStorage: [SpaceDeletionState]
    /// The app-wide preferences, or nil before the settings kept before the
    /// core owned them are imported. Preferences change together and seldom,
    /// so they are one observed value.
    private(set) var appPreferences: AppPreferences? {
        get { observed(\.appPreferencesStorage, as: \.appPreferences) }
        set { publish(newValue, into: \.appPreferencesStorage, as: \.appPreferences) }
    }
    @ObservationIgnored private var appPreferencesStorage: AppPreferences?
    /// The Space a launch opens.
    private(set) var defaultSpaceID: UUID? {
        get { observed(\.defaultSpaceIDStorage, as: \.defaultSpaceID) }
        set { publish(newValue, into: \.defaultSpaceIDStorage, as: \.defaultSpaceID) }
    }
    @ObservationIgnored private var defaultSpaceIDStorage: UUID?
    /// The session is still the disposable first-install seed.
    private(set) var isDisposableSeed: Bool {
        get { observed(\.isDisposableSeedStorage, as: \.isDisposableSeed) }
        set { publish(newValue, into: \.isDisposableSeedStorage, as: \.isDisposableSeed) }
    }
    @ObservationIgnored private var isDisposableSeedStorage: Bool
    /// Advances once for each batch of the core's changes that changed the
    /// session, after the batch is applied.
    private(set) var sessionRevision: UInt64 {
        get { observed(\.sessionRevisionStorage, as: \.sessionRevision) }
        set { publish(newValue, into: \.sessionRevisionStorage, as: \.sessionRevision) }
    }
    @ObservationIgnored private var sessionRevisionStorage: UInt64 = 0
    /// Whether a change of the batch being applied changed the session.
    @ObservationIgnored private var changedInBatch = false

    /// Every tab the workspace holds, open or archived.
    var tabIDs: [UUID] {
        spaces.models.flatMap(\.tabIDs)
    }

    // MARK: - Initializers

    init(_ change: WorkspaceOpened) {
        id = change.workspaceID
        kind = change.kind
        spaces = ObservedList(change.session.spaces)
        spaceDeletionsStorage = change.session.spaceDeletions
        appPreferencesStorage = change.session.appPreferences
        defaultSpaceIDStorage = change.session.defaultSpaceID
        isDisposableSeedStorage = change.session.disposableSeedMarker != nil
    }

    // MARK: - Actions - Reading

    /// Whether any Space of the workspace holds the tab, open or archived.
    func holds(tabID: UUID) -> Bool {
        spaces.models.contains { $0.holds(tabID: tabID) }
    }

    /// Whether any Space of the workspace holds the tab open.
    func holdsOpen(tabID: UUID) -> Bool {
        spaces.models.contains { $0.tabs.contains(tabID) }
    }

    // MARK: - Actions - Batches

    /// A change of the batch being applied changed the session.
    func sessionChanged() {
        changedInBatch = true
    }

    /// The batch ended: the session announces itself once when a change of
    /// the batch changed it. Answers whether it did.
    @discardableResult
    func finishBatch() -> Bool {
        guard changedInBatch else { return false }
        changedInBatch = false
        sessionRevision &+= 1
        return true
    }

    // MARK: - Actions - Changes

    /// The workspace joined again: it takes the whole session, keeping the
    /// object of every record the session still holds.
    func apply(_ change: WorkspaceOpened) {
        precondition(change.workspaceID == id, "A WorkspaceModel takes only its own workspace's session.")
        spaces.replace(with: change.session.spaces)
        apply(
            WorkspaceChanged(
                workspaceID: id, defaultSpaceID: change.session.defaultSpaceID,
                isDisposableSeed: change.session.disposableSeedMarker != nil,
                spaceDeletions: change.session.spaceDeletions))
        apply(AppPreferencesChanged(workspaceID: id, preferences: change.session.appPreferences))
    }

    func apply(_ change: WorkspaceChanged) {
        defaultSpaceID = change.defaultSpaceID
        isDisposableSeed = change.isDisposableSeed
        spaceDeletions = change.spaceDeletions
    }

    func apply(_ change: AppPreferencesChanged) {
        appPreferences = change.preferences
    }

    /// The `removed` Spaces are gone and each `added` Space arrives whole
    /// after the Spaces that stay. A Space named in both arrives again whole
    /// and keeps its object, which takes the Space's new records.
    func apply(_ change: SpacesChanged) {
        let gone = Set(change.removed)
        let staying = spaces.models.map(\.id).filter { !gone.contains($0) }
        let stayingIDs = Set(staying)
        let arriving = Set(change.added.map(\.id))
        let order = change.order ?? staying + change.added.map(\.id).filter { !stayingIDs.contains($0) }
        spaces.apply(updated: change.added, removed: change.removed.filter { !arriving.contains($0) }, order: order)
    }
}

extension WorkspaceModel: BrowserStoreFirstObservable {}
