import Foundation
import Observation

/// A Space of the read model. Its settings, each tab and each folder are
/// objects of their own, its sidebar lists are observed apart, and its
/// history and archive are kept apart, so a change notifies only the readers
/// of what it changed: a tab's new title redraws that tab's row, a move
/// redraws the one list it moves within, and a visit never redraws the
/// sidebar. Each of its
/// own values is stored before it is announced; see
/// `BrowserStoreFirstObservable`.
@MainActor
@Observable
final class SpaceModel: ObservedModel, Identifiable {
    // MARK: - Variables

    let id: UUID
    let settings: SpaceSettingsModel
    let tabs: ObservedList<TabStateModel>
    let folders: ObservedList<FolderStateModel>
    /// What the sidebar lists, as the core publishes it.
    let sidebar: SidebarModel
    let history: HistoryModel
    let archive: ArchiveModel
    private(set) var profileID: UUID {
        get { observed(\.profileIDStorage, as: \.profileID) }
        set { publish(newValue, into: \.profileIDStorage, as: \.profileID) }
    }
    @ObservationIgnored private var profileIDStorage: UUID
    /// What a person chose for each split. Membership stays on the tabs.
    private(set) var splitGroups: [SplitGroupState] {
        get { observed(\.splitGroupsStorage, as: \.splitGroups) }
        set { publish(newValue, into: \.splitGroupsStorage, as: \.splitGroups) }
    }
    @ObservationIgnored private var splitGroupsStorage: [SplitGroupState]

    var value: SpaceState {
        SpaceState(
            id: id, profileID: profileID, settings: settings.value, folders: folders.values, tabs: tabs.values,
            splitGroups: splitGroups, archivedTabs: archive.entries, history: history.entries,
            sidebar: sidebar.outline(folders: folders.models))
    }

    /// Every tab the Space holds, open or archived.
    var tabIDs: [UUID] {
        tabs.models.map(\.id) + archive.entries.map(\.tab.id)
    }

    // MARK: - Initializers

    init(_ value: SpaceState) {
        id = value.id
        profileIDStorage = value.profileID
        settings = SpaceSettingsModel(value.settings)
        tabs = ObservedList(value.tabs)
        folders = ObservedList(value.folders)
        sidebar = SidebarModel(value.sidebar)
        splitGroupsStorage = value.splitGroups
        history = HistoryModel(value.history)
        archive = ArchiveModel(value.archivedTabs)
    }

    /// Takes the Space again whole, keeping the object of every record it
    /// still holds.
    func update(_ value: SpaceState) {
        precondition(value.id == id, "A SpaceModel takes only its own Space's values.")
        profileID = value.profileID
        settings.update(value.settings)
        tabs.replace(with: value.tabs)
        folders.replace(with: value.folders)
        sidebar.replace(with: value.sidebar)
        splitGroups = value.splitGroups
        history.replace(with: value.history)
        archive.replace(with: value.archivedTabs)
    }

    // MARK: - Actions - Reading

    /// Whether the Space holds the tab, open or archived.
    func holds(tabID: UUID) -> Bool {
        tabs.contains(tabID) || archive.contains(tabID: tabID)
    }

    // MARK: - Actions - Changes

    func apply(_ change: SpaceSettingsChanged) {
        settings.update(change.settings)
    }

    func apply(_ change: TabsChanged) {
        tabs.apply(updated: change.updated, removed: change.removed, order: change.order)
    }

    func apply(_ change: FoldersChanged) {
        folders.apply(updated: change.updated, removed: change.removed, order: change.order)
    }

    func apply(_ change: SplitGroupsChanged) {
        splitGroups = change.groups
    }

    func apply(_ change: SidebarChanged) {
        sidebar.apply(change)
    }

    func apply(_ change: HistoryChanged) {
        history.apply(change)
    }

    func apply(_ change: ArchiveChanged) {
        archive.apply(change)
    }
}

extension SpaceModel: BrowserStoreFirstObservable {}
