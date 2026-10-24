import Foundation
import Observation
import XCTest

@testable import Crest

/// The read model the core's changes update. Fed the batches the core
/// drained, from the workspace's opening on, it holds what the Swift session
/// copy holds; a batch applied twice changes nothing; and a change notifies
/// only the objects whose values it really changes.
@MainActor
final class CoreReadModelTests: XCTestCase {

    func testWindowSelectionReadsObserveOnlyTheirSpace() throws {
        let store = BrowserStore(seed: .preview, core: CrestCore())
        let spaces = store.spaceModels
        let first = try XCTUnwrap(spaces.first)
        let other = try XCTUnwrap(spaces.dropFirst().first)
        let selected = try XCTUnwrap(store.selectedTabID(in: first.id))
        let next = try XCTUnwrap(first.tabs.models.first { $0.id != selected })
        let window = try XCTUnwrap(store.windowModel)
        let spaceSelection = tripwire { _ = store.selectedSpaceID }
        let tabSelection = tripwire { _ = store.selectedTabID(in: first.id) }
        let otherTabSelection = tripwire { _ = store.selectedTabID(in: other.id) }
        let cards = tripwire { _ = window.cards(in: first.id) }
        let otherCards = tripwire { _ = window.cards(in: other.id) }

        XCTAssertTrue(store.activateSessionTab(next.id, in: first.id))

        XCTAssertEqual(store.selectedSpaceID, first.id)
        XCTAssertEqual(store.selectedTabID(in: first.id), next.id)
        XCTAssertTrue(tabSelection.isTripped)
        XCTAssertTrue(cards.isTripped)
        XCTAssertFalse(spaceSelection.isTripped)
        XCTAssertFalse(otherTabSelection.isTripped)
        XCTAssertFalse(otherCards.isTripped)

        let spaceChange = tripwire { _ = store.selectedSpaceID }
        store.selectSpace(other.id)
        XCTAssertTrue(spaceChange.isTripped)
        XCTAssertEqual(store.selectedSpaceID, other.id)
    }

    func testAChangeNotifiesOnlyTheObjectsWhoseValuesItChanges() throws {
        let core = CrestCore()
        let store = BrowserStore(seed: .preview, core: core)
        let other = store.makeWindowStore()
        let space = try XCTUnwrap(core.state.workspaces[store.window.workspaceID]?.spaces.models.first)
        let tabs = space.tabs.models
        XCTAssertGreaterThan(tabs.count, 1)
        let (renamed, sibling) = (tabs[0], tabs[1])

        // An equal value notifies no one, whether it reaches the model itself
        // or arrives as a change.
        XCTAssertFalse(notifies({ _ = renamed.value }) { renamed.update(renamed.value) })
        XCTAssertFalse(
            notifies(core.state) {
                TabsChanged(
                    workspaceID: store.window.workspaceID, spaceID: space.id, updated: space.tabs.values,
                    removed: [], order: nil
                )
                .apply(to: core.state)
            })

        // A new custom title notifies the readers of that title and no one else.
        let customTitle = tripwire { _ = renamed.customTitle }
        let renamedURL = tripwire { _ = renamed.url }
        let siblingTab = tripwire { _ = sibling.value }
        let list = tripwire { _ = space.tabs.models }
        let spaces = tripwire { _ = core.state.workspaces[store.window.workspaceID]?.spaces.models }
        let records = tripwire {
            _ = space.settings.value
            _ = space.history.entries
            _ = space.archive.entries
            _ = space.folders.models
        }
        let otherWindow = tripwire { _ = core.state.windows[other.windowID]?.value }
        XCTAssertTrue(
            store.setTabCustomTitle("Renamed", for: renamed.id, in: space.id))
        XCTAssertEqual(renamed.customTitle, "Renamed")
        XCTAssertTrue(customTitle.isTripped)
        XCTAssertFalse(renamedURL.isTripped)
        XCTAssertFalse(siblingTab.isTripped)
        XCTAssertFalse(list.isTripped)
        XCTAssertFalse(spaces.isTripped)
        XCTAssertFalse(records.isTripped)

        // Showing a tab in one window never notifies another window's readers.
        let shown = tripwire { _ = core.state.windows[store.windowID]?.value }
        XCTAssertTrue(store.activateSessionTab(sibling.id, in: space.id))
        XCTAssertTrue(shown.isTripped)
        XCTAssertFalse(otherWindow.isTripped)

        // A lookup observes which tabs the Space holds, not their order.
        let order = tripwire { _ = space.tabs.models }
        let lookup = tripwire { _ = space.tabs.model(renamed.id) }
        XCTAssertEqual(sibling.placement, renamed.placement)
        XCTAssertTrue(store.moveSessionTab(sibling.id, in: space.id, to: sibling.placement, before: renamed.id))
        XCTAssertTrue(order.isTripped)
        XCTAssertFalse(lookup.isTripped)

        // A lookup observes only whether its own tab joins or leaves: another
        // tab opening and closing never notifies it.
        let opened = try XCTUnwrap(
            store.openSessionTab(.page(URL(string: "https://joined.example/")!, title: "Joined"), in: space.id))
        let openedLookup = tripwire { _ = space.tabs.model(opened) }
        XCTAssertTrue(store.closeTab(opened, in: space.id))
        XCTAssertTrue(openedLookup.isTripped)
        XCTAssertFalse(lookup.isTripped)
    }

    /// The window's model is written by hand for its per-tab slots, so it must
    /// carry every field of the core's `WindowState`: each one is stored, and
    /// a value that differs in every field reads back whole.
    func testTheWindowModelCarriesEveryFieldOfItsRecord() {
        let value = WindowState(
            id: UUID(), workspaceID: UUID(), shownSpaceID: UUID(),
            shownTabs: [ShownTab(spaceID: UUID(), tabID: UUID())],
            splitColumnShares: [SplitColumnShares(groupID: UUID(), shares: [0.5, 0.5])],
            cards: [ShownCards(spaceID: UUID(), tabIDs: [UUID(), UUID()], splitGroupID: UUID())],
            unavailableCommands: [.duplicateTab, .archiveTab])
        let model = WindowStateModel(value)
        let stored = Set(Mirror(reflecting: model).children.compactMap(\.label))
        for case let field? in Mirror(reflecting: value).children.map(\.label) {
            XCTAssertTrue(
                stored.contains(field) || stored.contains("\(field)Storage"),
                "WindowStateModel does not keep WindowState.\(field).")
        }
        XCTAssertEqual(model.value, value)
        let next = WindowState(
            id: value.id, workspaceID: UUID(), shownSpaceID: UUID(),
            shownTabs: [ShownTab(spaceID: UUID(), tabID: nil)], splitColumnShares: [], cards: [],
            unavailableCommands: [.reloadPage])
        model.update(next)
        XCTAssertEqual(model.value, next)
        XCTAssertFalse(model.shownTabIDs.contains(value.shownTabs[0].tabID ?? UUID()))
    }

    /// SwiftUI can render while a change is being announced, and a view it
    /// renders there must read the new value, or it keeps the old one and is
    /// never told of the change again. Every kind of read-model object stores
    /// what a change brings before it announces the change.
    func testEveryReadModelObjectStoresAChangeBeforeAnnouncingIt() throws {
        let core = CrestCore.hostingPages()
        var batches: [[Change]] = []
        core.batchApplied = { batches.append($0) }
        let session = SessionState.Seed.preview
        let store = BrowserStore(seed: session, images: [session.spaces[0].tabs[7].id: Data([1])], core: core)
        let state = core.state
        let workspace = try XCTUnwrap(state.workspaces[store.window.workspaceID])
        let space = try XCTUnwrap(workspace.spaces.model(session.spaces[0].id))
        let other = try XCTUnwrap(workspace.spaces.model(session.spaces[1].id))
        let tabs = space.tabs.models
        let (pinned, nextPinned, current) = (tabs[0], tabs[1], tabs[7])
        let folder = try XCTUnwrap(space.folders.models.first)
        let window = try XCTUnwrap(state.windows[store.windowID])
        let page = try XCTUnwrap(store.openReportingPage(for: pinned.id, in: space.id))
        let pageState = try XCTUnwrap(page.state)

        assertStoredFirst(
            "TabStateModel", reading: { pinned.customTitle },
            after: {
                store.setTabCustomTitle("Stored", for: pinned.id, in: space.id)
            })
        assertStoredFirst(
            "FolderStateModel", reading: { folder.isCollapsed },
            after: {
                store.setFolderCollapsed(folder.id, in: space.id, isCollapsed: !folder.isCollapsed)
            })
        assertStoredFirst(
            "SpaceSettingsModel", reading: { space.settings.name },
            after: {
                store.updateSpaceIdentity(space.id, name: "Stored", symbol: "book", accent: .teal)
            })
        assertStoredFirst(
            "WindowStateModel", reading: { window.shownTabs },
            after: {
                store.activateSessionTab(nextPinned.id, in: space.id)
            })
        assertStoredFirst(
            "ObservedSet", reading: { window.shownTabIDs.contains(pinned.id) },
            after: {
                store.activateSessionTab(pinned.id, in: space.id)
            })
        assertStoredFirst(
            "SidebarListModel", reading: { space.sidebar.section(.current).rows.map(\.id) },
            after: {
                _ = store.openSessionTab(.page(URL(string: "https://listed.example/")!, title: "Listed"), in: space.id)
            })
        assertStoredFirst(
            "PageStateModel", reading: { pageState.live.title },
            after: {
                store.finishNavigation(of: page, to: URL(string: "https://stored.example/")!, titled: "Stored")
            })
        assertStoredFirst(
            "ObservedList order", reading: { space.tabs.models.map(\.id) },
            after: {
                _ = store.moveSessionTab(nextPinned.id, in: space.id, to: .pinned, before: pinned.id)
            })
        assertStoredFirst(
            "FaviconAssets", reading: { state.favicons.image(of: current.id) },
            after: {
                store.setTabFavicon(Data([2]), iconAccent: nil, for: current.id, in: space.id)
            })
        assertStoredFirst(
            "WorkspaceModel", reading: { workspace.defaultSpaceID },
            after: {
                store.setDefaultSpace(workspace.defaultSpaceID == other.id ? space.id : other.id)
            })
        assertStoredFirst(
            "HistoryModel", reading: { space.history.entries.count },
            after: {
                store.seedVisit(to: URL(string: "https://visited.example/")!, titled: "Visited", in: space.id)
            })
        assertStoredFirst(
            "ArchiveModel", reading: { space.archive.entries.count },
            after: {
                store.closeTab(current.id, in: space.id)
            })

        // The rest is changed directly, on a read model no workspace's windows follow.
        let detached = CoreState()
        for batch in batches { apply(batch, to: detached) }
        let detachedSpace = try XCTUnwrap(detached.workspaces[workspace.id]?.spaces.model(space.id))
        assertStoredFirst(
            "ObservedList membership", reading: { detachedSpace.tabs.model(pinned.id) != nil },
            after: {
                detachedSpace.apply(
                    TabsChanged(
                        workspaceID: workspace.id, spaceID: space.id, updated: [], removed: [pinned.id], order: nil))
            })
        let split = SplitGroupState(
            id: UUID(), customTitle: "Stored", titleModifiedAt: nil, customIconSymbol: nil, iconModifiedAt: nil,
            tint: nil, tintModifiedAt: nil, displayTitle: "Stored", displayEmojiIcon: nil)
        assertStoredFirst(
            "SpaceModel", reading: { detachedSpace.splitGroups },
            after: {
                detachedSpace.apply(SplitGroupsChanged(workspaceID: workspace.id, spaceID: space.id, groups: [split]))
            })
        let workspaceID = UUID()
        assertStoredFirst(
            "CoreState.workspaces", reading: { detached.workspaces[workspaceID] != nil },
            after: {
                WorkspaceOpened(
                    workspaceID: workspaceID, kind: .private,
                    session: SessionState(
                        spaces: [], defaultSpaceID: nil, disposableSeedMarker: nil, spaceDeletions: [],
                        appPreferences: nil)
                ).apply(to: detached)
            })
        let windowID = UUID()
        assertStoredFirst(
            "CoreState.windows", reading: { detached.windows[windowID] != nil },
            after: {
                WindowChanged(
                    window: WindowState(
                        id: windowID, workspaceID: workspaceID, shownSpaceID: UUID(), shownTabs: [],
                        splitColumnShares: [], cards: [], unavailableCommands: [])
                ).apply(to: detached)
            })
        let pageID = UUID()
        assertStoredFirst(
            "CoreState.pages", reading: { detached.pages[pageID] != nil },
            after: {
                PageOpened(
                    page: PageState(
                        id: pageID, workspaceID: workspaceID, spaceID: UUID(), tabID: nil, engine: .webKit,
                        phase: .opening, live: .blank)
                ).apply(to: detached)
            })
        assertStoredFirst(
            "CoreState values", reading: { detached.storageFailure },
            after: {
                StorageFailed(reason: .diskFull).apply(to: detached)
            })
    }

    // MARK: - Helpers

    /// Changes something with `change` and asserts that a reader told of the
    /// change, while it is announced, reads what `read` reads after it.
    private func assertStoredFirst<Value: Equatable>(
        _ kind: String, reading read: @escaping @MainActor () -> Value, after change: () -> Void,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let before = read()
        let announcement = Announcement(reading: read)
        change()
        let after = read()
        XCTAssertNotEqual(after, before, "\(kind): the change changed nothing.", file: file, line: line)
        XCTAssertEqual(
            announcement.seen, after, "\(kind): a reader told of the change read the old value.", file: file,
            line: line)
    }

    private func apply(_ batch: [Change], to state: CoreState) {
        for change in batch { change.apply(to: state) }
        state.finishBatch()
    }

    /// The workspace's records and members, and every window's, as values.
    private static func values(of state: CoreState, _ workspaceID: UUID) -> [String] {
        guard let workspace = state.workspaces[workspaceID] else { return [] }
        return [
            String(describing: workspace.spaces.values), String(describing: workspace.defaultSpaceID),
            String(describing: workspace.isDisposableSeed), String(describing: workspace.spaceDeletions),
            String(describing: workspace.appPreferences),
            String(describing: state.windows.values.map(\.value).sorted { $0.id.uuidString < $1.id.uuidString }),
        ]
    }

    /// Whether `body` notifies any reader of everything `state` holds.
    private func notifies(_ state: CoreState, _ body: () -> Void) -> Bool {
        notifies(
            {
                for workspace in state.workspaces.values {
                    _ = workspace.spaces.values
                    _ = (workspace.defaultSpaceID, workspace.isDisposableSeed, workspace.spaceDeletions)
                    _ = workspace.appPreferences
                    for space in workspace.spaces.models {
                        _ = (space.splitGroups, space.history.entries, space.archive.entries)
                        for tab in space.tabs.models { _ = state.favicons.image(of: tab.id) }
                    }
                }
                _ = state.windows.values.map(\.value)
            }, body)
    }

    private func notifies(_ read: () -> Void, _ body: () -> Void) -> Bool {
        let wire = tripwire(read)
        body()
        return wire.isTripped
    }

    private func tripwire(_ read: () -> Void) -> Tripwire {
        let wire = Tripwire()
        withObservationTracking(read) { wire.trip() }
        return wire
    }
}

/// What a reader read when it was told of a change, as SwiftUI reads when it
/// renders during the change's announcement.
@MainActor
private final class Announcement<Value> {
    private(set) var seen: Value?

    init(reading read: @escaping @MainActor () -> Value) {
        withObservationTracking {
            _ = read()
        } onChange: { [self] in
            MainActor.assumeIsolated { seen = read() }
        }
    }
}

/// Records that an observation fired. Observation calls it synchronously on
/// the main actor, before the change it reports.
private final class Tripwire: @unchecked Sendable {
    private(set) var isTripped = false

    func trip() {
        isTripped = true
    }
}
