import Foundation
import Observation

/// Observable browser state. Views read it directly. Managed state changes
/// arrive through `CrestCore`, each through its own
/// `apply(to:)` in a `Changes/Area/Change+CoreState.swift` file. It is
/// observable per entity: each workspace, Space, tab, folder and window is
/// an object of its own that notifies only when one of its values really
/// changes. Native domains update their own values, including download records and import review.
///
/// Every value is stored before it is announced, so a view that renders
/// while a change is announced reads the new value; see
/// `BrowserStoreFirstObservable`.
@MainActor
@Observable
final class CoreState {
    // MARK: - Variables

    /// Each workspace attached to this device, by workspace. The dictionary
    /// changes only when a workspace joins or leaves.
    var workspaces: [UUID: WorkspaceModel] { observed(\.workspacesStorage, as: \.workspaces) }
    @ObservationIgnored var workspacesStorage: [UUID: WorkspaceModel] = [:]
    /// The images tabs wear, which the platform keeps and the core never sees.
    let favicons = FaviconAssets()
    /// This run's download records, newest first.
    var downloads: [DownloadState] {
        get { observed(\.downloadsStorage, as: \.downloads) }
        set { publish(newValue, into: \.downloadsStorage, as: \.downloads) }
    }
    @ObservationIgnored private var downloadsStorage: [DownloadState] = []
    /// What each open window shows, by window. The dictionary changes only
    /// when a window opens or closes.
    var windows: [UUID: WindowStateModel] { observed(\.windowsStorage, as: \.windows) }
    @ObservationIgnored var windowsStorage: [UUID: WindowStateModel] = [:]
    /// Each page this device hosts, by page: its owner, its engine, where it
    /// stands there and its live state. The dictionary changes only when a
    /// page opens or goes, so a page's new title redraws only its readers.
    @ObservationIgnored var pageOrder: [UUID] = []
    var pages: [UUID: PageStateModel] { observed(\.pagesStorage, as: \.pages) }
    @ObservationIgnored var pagesStorage: [UUID: PageStateModel] = [:]
    /// WebKit's capabilities, as published when its binding registers.
    var engines: EngineRoster? {
        get { observed(\.enginesStorage, as: \.engines) }
        set { publish(newValue, into: \.enginesStorage, as: \.engines) }
    }
    @ObservationIgnored private var enginesStorage: EngineRoster?
    /// Whether agents may use Crest on this device, whether they may run
    /// scripts in pages, the Spaces they may reach and the agents the person
    /// allowed.
    var agentPreferences: AgentPreferences {
        get { observed(\.agentPreferencesStorage, as: \.agentPreferences) }
        set { publish(newValue, into: \.agentPreferencesStorage, as: \.agentPreferences) }
    }
    @ObservationIgnored private var agentPreferencesStorage = AgentPreferences(
        isOn: false, runsScripts: false, spaceIDs: [], agents: [])
    /// The agents connected now, with the tabs each uses.
    var agentSessions: [AgentSessionState] {
        get { observed(\.agentSessionsStorage, as: \.agentSessions) }
        set { publish(newValue, into: \.agentSessionsStorage, as: \.agentSessions) }
    }
    @ObservationIgnored private var agentSessionsStorage: [AgentSessionState] = []
    /// The newest file revision the core has on disk, counting the stored
    /// session's edits and this device's saved windows; zero before its first
    /// save and for a core that keeps nothing.
    var savedRevision: Int64 {
        get { observed(\.savedRevisionStorage, as: \.savedRevision) }
        set { publish(newValue, into: \.savedRevisionStorage, as: \.savedRevision) }
    }
    @ObservationIgnored private var savedRevisionStorage: Int64 = 0
    /// Why the core's last save failed, until a later save succeeds.
    var storageFailure: StorageFailure? {
        get { observed(\.storageFailureStorage, as: \.storageFailure) }
        set { publish(newValue, into: \.storageFailureStorage, as: \.storageFailure) }
    }
    @ObservationIgnored private var storageFailureStorage: StorageFailure?
    /// Why the core could not stage the session's latest edits for sync, until
    /// a later stage succeeds.
    var syncStagingFailure: SyncStagingFailure? {
        get { observed(\.syncStagingFailureStorage, as: \.syncStagingFailure) }
        set { publish(newValue, into: \.syncStagingFailureStorage, as: \.syncStagingFailure) }
    }
    @ObservationIgnored private var syncStagingFailureStorage: SyncStagingFailure?
    /// What the stored session's sync journal holds, as the core last
    /// published it: its records and those waiting to upload. Nil until the
    /// core attaches the journal, and for a core that keeps nothing.
    var syncJournal: SyncJournalChanged? {
        get { observed(\.syncJournalStorage, as: \.syncJournal) }
        set { publish(newValue, into: \.syncJournalStorage, as: \.syncJournal) }
    }
    @ObservationIgnored private var syncJournalStorage: SyncJournalChanged?
    /// The site permission choices each Space keeps, in the order the settings
    /// list them, as the native ledger last published them. A Space missing here keeps
    /// none.
    var sitePermissions: [UUID: [SitePermissionRecordState]] {
        get { observed(\.sitePermissionsStorage, as: \.sitePermissions) }
        set { publish(newValue, into: \.sitePermissionsStorage, as: \.sitePermissions) }
    }
    @ObservationIgnored private var sitePermissionsStorage: [UUID: [SitePermissionRecordState]] = [:]
    /// Advances with every native site permission change, so a view that
    /// asks for a decision redraws when any choice changes.
    var sitePermissionRevision: UInt64 {
        get { observed(\.sitePermissionRevisionStorage, as: \.sitePermissionRevision) }
        set { publish(newValue, into: \.sitePermissionRevisionStorage, as: \.sitePermissionRevision) }
    }
    @ObservationIgnored private var sitePermissionRevisionStorage: UInt64 = 0
    /// Native fixed bindings, filtered by WebKit's published capabilities.
    var shortcutBindings: [ShortcutBinding] {
        ShortcutCommand.all.filter { $0.isOffered(in: self) }.map {
            ShortcutBinding(command: $0, keys: $0.defaultShortcuts.first { $0.platform == .current }?.keys)
        }
    }
    var shortcuts: [ShortcutCommand: ShortcutBinding] {
        Dictionary(uniqueKeysWithValues: shortcutBindings.map { ($0.command, $0) })
    }
    /// Native import queue and review, or nil while setup
    /// is not open.
    var importFlow: ImportFlowState? {
        get { observed(\.importFlowStorage, as: \.importFlow) }
        set { publish(newValue, into: \.importFlowStorage, as: \.importFlow) }
    }
    @ObservationIgnored private var importFlowStorage: ImportFlowState?
}

extension CoreState: BrowserStoreFirstObservable {}
