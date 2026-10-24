import Foundation
import Observation
import XCTest

@testable import Crest

/// The sidebar's tripwires: each kind of change, driven through the core,
/// redraws only the sidebar bodies the read model's criteria allow.
/// `SidebarBodies` reads what each real sidebar view's body reads, through
/// the same objects and functions, and hands each child the inputs the view
/// hands it.
extension CoreReadModelTests {
    func testEachChangeRedrawsOnlyTheSidebarBodiesItConcerns() throws {
        let bench = SidebarChangeBench(session: SidebarChangeFixture.composed())
        // The window starts on a plain open tab, so showing another moves the
        // shown state between two rows. A split member also redraws its split.
        bench.store.activateSessionTab(bench.currentTabs[11].id, in: bench.space.id)
        let context = try XCTUnwrap(bench.store.sidebarListContext(for: bench.space.id))
        let bodies = SidebarBodies(mirroring: context)
        for edit in SidebarChange.all {
            let limits = try XCTUnwrap(SidebarLimits.all[edit.name], "\(edit.name) has no limits.")
            let measured = bodies.measure(edit, on: bench, runs: 2)
            XCTAssertTrue(measured.changed, "\(edit.name) changed nothing.")
            for kind in SidebarBody.allCases {
                XCTAssertLessThanOrEqual(
                    measured.maximum(kind), limits.allowed[kind] ?? 0, "\(edit.name) redrew too many \(kind) bodies.")
                if let mounts = limits.mounts[kind] {
                    XCTAssertLessThanOrEqual(measured.maximumMounts(kind), mounts, "\(edit.name) added \(kind) bodies.")
                } else if limits.mounts.isEmpty {
                    XCTAssertEqual(measured.maximumMounts(kind), 0, "\(edit.name) added \(kind) bodies.")
                }
            }
        }
    }
}

/// A kind of view the sidebar draws.
enum SidebarBody: String, CaseIterable {
    /// The tab list, which reads only whether the saved section is open.
    case list
    /// The seam between the saved and current sections.
    case seam
    /// A section's drop container, which reads nothing of its own.
    case container
    /// The rows of one list the core publishes, or the pinned grid.
    case section
    /// A tab, split or folder row, a split's member row, or a pinned tile.
    case row
}

/// The bodies each kind of change may evaluate again, and add, in the sidebar.
struct SidebarLimits {
    // MARK: - Static Variables

    /// The limits by edit: a change of what one tab shows redraws that tab's
    /// row alone, showing another tab redraws its two rows and no list, a move
    /// redraws only the list it moves within, a collapse only the folder's row,
    /// and a change that concerns no row redraws nothing. The Space's header
    /// and switcher move onto the read model with the next slice.
    static let all: [String: SidebarLimits] = [
        "E1 title report": SidebarLimits(allowed: [.row: 2]),
        "E2 committed navigation": SidebarLimits(allowed: [.row: 3]),
        "E2 Start Page to web page": SidebarLimits(allowed: [.section: 1, .row: 3], mounts: [.row: 1]),
        "E3 favicon, first": SidebarLimits(allowed: [.row: 2]),
        "E3 favicon, replaced": SidebarLimits(allowed: [.row: 2]),
        "E4 history visit": SidebarLimits(allowed: [:]),
        "E5 show another tab": SidebarLimits(allowed: [.row: 2]),
        "E6 move within section": SidebarLimits(allowed: [.section: 1]),
        "E7 collapse folder": SidebarLimits(allowed: [.row: 1], mounts: [.section: .max, .row: .max]),
        "E8 rename Space": SidebarLimits(allowed: [:]),
        "E9 loading toggle": SidebarLimits(allowed: [.row: 2]),
        "E10 selection in window B": SidebarLimits(allowed: [:]),
    ]

    // MARK: - Variables

    /// The bodies of each kind a run may evaluate again; any other kind, none.
    let allowed: [SidebarBody: Int]
    /// The bodies of each kind a run may add; with none named, a run adds none.
    var mounts: [SidebarBody: Int] = [:]
}

// MARK: - Bodies

/// A model of SwiftUI's body evaluations over the real sidebar. A view reads
/// what its body reads under observation tracking and hands each child its
/// inputs. It evaluates again when something it read changes, or when its
/// parent evaluates and hands it inputs that differ; a child whose inputs are
/// equal is left alone, as SwiftUI leaves it.
@MainActor
final class SidebarBodies {
    // MARK: - Types

    /// A view: its kind, or nil for the root, which is never counted, and
    /// what its body reads, returning its children.
    struct Node {
        let kind: SidebarBody?
        let read: @MainActor () -> [Child]
    }

    /// A child a body hands out, by identity, with its inputs.
    struct Child {
        let key: String
        let input: AnyEquatable
        let node: Node
    }

    private final class Mounted {
        var node: Node
        var input: AnyEquatable
        let depth: Int
        var children: [String] = []
        var generation = 0

        init(node: Node, input: AnyEquatable, depth: Int) {
            self.node = node
            self.input = input
            self.depth = depth
        }
    }

    // MARK: - Variables

    private var mounted: [String: Mounted] = [:]
    private var dirty: Set<String> = []
    /// Bodies evaluated again, and bodies evaluated for the first time, by kind.
    private(set) var evaluations: [SidebarBody: Int] = [:]
    private(set) var mounts: [SidebarBody: Int] = [:]

    // MARK: - Initializers

    init(root: Node) {
        mounted["root"] = Mounted(node: root, input: AnyEquatable("root"), depth: 0)
        evaluate("root", isMount: true)
        reset()
    }

    // MARK: - Actions - Evaluation

    /// Evaluates every body a change invalidated, parents first.
    func settle() {
        while let key = dirty.min(by: { (mounted[$0]?.depth ?? 0) < (mounted[$1]?.depth ?? 0) }) {
            dirty.remove(key)
            if mounted[key] != nil { evaluate(key, isMount: false) }
        }
    }

    func reset() {
        evaluations = [:]
        mounts = [:]
    }

    private func evaluate(_ key: String, isMount: Bool) {
        guard let view = mounted[key] else { return }
        dirty.remove(key)
        if let kind = view.node.kind {
            if isMount { mounts[kind, default: 0] += 1 } else { evaluations[kind, default: 0] += 1 }
        }
        view.generation += 1
        let generation = view.generation
        var children: [Child] = []
        withObservationTracking {
            children = view.node.read()
        } onChange: { [weak self] in
            MainActor.assumeIsolated { self?.invalidate(key, generation: generation) }
        }
        let keys = Set(children.map(\.key))
        for gone in view.children where !keys.contains(gone) { unmount(gone) }
        view.children = children.map(\.key)
        for child in children {
            if let existing = mounted[child.key] {
                guard existing.input != child.input else { continue }
                existing.input = child.input
                existing.node = child.node
                evaluate(child.key, isMount: false)
            } else {
                mounted[child.key] = Mounted(node: child.node, input: child.input, depth: view.depth + 1)
                evaluate(child.key, isMount: true)
            }
        }
    }

    /// A body's earlier reads no longer count once it has evaluated again.
    private func invalidate(_ key: String, generation: Int) {
        guard mounted[key]?.generation == generation else { return }
        dirty.insert(key)
    }

    private func unmount(_ key: String) {
        guard let view = mounted.removeValue(forKey: key) else { return }
        dirty.remove(key)
        for child in view.children { unmount(child) }
    }
}

/// A value compared through its own `Equatable` conformance.
struct AnyEquatable: Equatable {
    private let value: any Equatable

    init(_ value: some Equatable) {
        self.value = value
    }

    static func == (lhs: AnyEquatable, rhs: AnyEquatable) -> Bool {
        lhs.value.isEqual(to: rhs.value)
    }
}

extension Equatable {
    fileprivate func isEqual(to other: any Equatable) -> Bool {
        (other as? Self) == self
    }
}

// MARK: - Mirror

extension SidebarBodies {
    /// The views the real sidebar draws over one Space in one window: the
    /// pinned grid and the tab list, each reading what its body reads.
    convenience init(mirroring context: BrowserSidebarListContext) {
        let interaction = BrowserSidebarInteractionState.connected(to: context.browser)
        var generation = 0
        self.init(
            root: Node(kind: nil) {
                [
                    Child(
                        key: "pinned", input: AnyEquatable("pinned"),
                        node: Node(kind: .section) {
                            let space = context.space
                            return space.sidebar.section(.pinned).rows.compactMap { space.tabs.model($0.id) }.map {
                                tab in
                                Child(
                                    key: "tile-\(tab.id)", input: AnyEquatable(ObjectIdentifier(tab)),
                                    node: Node(kind: .row) {
                                        SidebarReads.tile(tab, in: context)
                                        return []
                                    })
                            }
                        }),
                    Child(
                        key: "list", input: AnyEquatable("list"),
                        node: Node(kind: .list) {
                            let isSavedTabsExpanded = context.space.settings.isSavedTabsExpanded
                            generation += 1
                            var children: [Child] = []
                            if isSavedTabsExpanded {
                                children.append(
                                    SidebarBodies.container(
                                        "saved", list: context.space.sidebar.section(.saved), generation: generation,
                                        context: context, interaction: interaction))
                            }
                            children.append(
                                Child(
                                    key: "seam", input: AnyEquatable(isSavedTabsExpanded),
                                    node: Node(kind: .seam) {
                                        SidebarReads.seam(in: context, isSavedTabsExpanded: isSavedTabsExpanded)
                                        return []
                                    }))
                            children.append(
                                SidebarBodies.container(
                                    "current", list: context.space.sidebar.section(.current), generation: generation,
                                    context: context, interaction: interaction))
                            return children
                        }),
                ]
            })
    }

    /// A section's drop container, which the list hands new inputs each time
    /// it draws, and which hands its rows view the list it draws.
    private static func container(
        _ key: String, list: SidebarListModel, generation: Int, context: BrowserSidebarListContext,
        interaction: BrowserSidebarInteractionState
    ) -> Child {
        Child(
            key: "container-\(key)", input: AnyEquatable(generation),
            node: Node(kind: .container) {
                [rows(list, key: "rows-\(key)", context: context, interaction: interaction)]
            })
    }

    /// The rows view of one list the core publishes, handed the list itself.
    private static func rows(
        _ list: SidebarListModel, key: String, context: BrowserSidebarListContext,
        interaction: BrowserSidebarInteractionState
    ) -> Child {
        Child(
            key: key, input: AnyEquatable(ObjectIdentifier(list)),
            node: Node(kind: .section) {
                BrowserSidebarListItem.items(
                    of: list, in: context.space, namesFollowingTabs: context.capabilities.showsRowDropIndicators
                ).map {
                    Child(
                        key: "\(key)-\($0.id)", input: AnyEquatable($0),
                        node: node(for: $0, context: context, interaction: interaction))
                }
            })
    }

    private static func node(
        for item: BrowserSidebarListItem, context: BrowserSidebarListContext,
        interaction: BrowserSidebarInteractionState, keptTabID: UUID? = nil
    ) -> Node {
        switch item.content {
        case .tab(let tab):
            Node(kind: .row) {
                SidebarReads.tabRow(tab, in: context, isSplitGroupMember: false)
                return []
            }
        case .split(let groupID, let members):
            Node(kind: .row) {
                SidebarReads.splitRow(groupID, members: members, in: context, interaction: interaction)
                return members.map { member in
                    Child(
                        key: "member-\(member.id)", input: AnyEquatable(ObjectIdentifier(member)),
                        node: Node(kind: .row) {
                            SidebarReads.tabRow(member, in: context, isSplitGroupMember: true)
                            return []
                        })
                }
            }
        case .folder(let folder):
            Node(kind: .row) {
                let configuration = SidebarReads.folderRow(
                    folder, depth: item.depth, in: context, interaction: interaction, inheritedKeptTabID: keptTabID)
                var children = [
                    Child(
                        key: "count-\(folder.id)", input: AnyEquatable(ObjectIdentifier(folder)),
                        node: Node(kind: .row) {
                            _ = context.space.tabIDs(inFolder: folder.id).count
                            return []
                        })
                ]
                let state = interaction.collapsedFolderVisibility(for: configuration.folderRuntimeAssignment).state
                if configuration.showsContents {
                    let key = "folder-\(folder.id)"
                    children.append(rows(configuration.inside, key: key, context: context, interaction: interaction))
                } else if let kept = configuration.keptItem(for: state) {
                    let keptTabID = configuration.keptTabID(for: state)
                    children.append(
                        Child(
                            key: "kept-\(folder.id)",
                            input: AnyEquatable([AnyEquatable(kept), AnyEquatable(keptTabID)]),
                            node: node(for: kept, context: context, interaction: interaction, keptTabID: keptTabID)))
                }
                return children
            }
        }
    }

    /// Runs `edit` `runs` times on `bench`, each after its preparation, and
    /// counts the bodies each run evaluated.
    func measure(_ edit: SidebarChange, on bench: SidebarChangeBench, runs: Int) -> SidebarMeasurement {
        var measurement = SidebarMeasurement(name: edit.name)
        for run in 0..<runs {
            edit.prepare?(bench, run)
            settle()
            reset()
            bench.clearChanges()
            let start = ContinuousClock.now
            edit.perform(bench, run)
            let applied = start.duration(to: .now)
            settle()
            measurement.record(
                evaluations: evaluations, mounts: mounts, applied: applied, changes: bench.changeKinds)
        }
        return measurement
    }
}

/// What one edit's runs evaluated.
struct SidebarMeasurement {
    let name: String
    private(set) var evaluations: [[SidebarBody: Int]] = []
    private(set) var mounts: [[SidebarBody: Int]] = []
    private(set) var applied: [Duration] = []
    private(set) var changes: Set<String> = []

    init(name: String) {
        self.name = name
    }

    /// Whether the runs changed anything the core reports.
    var changed: Bool { !changes.isEmpty }

    mutating func record(
        evaluations: [SidebarBody: Int], mounts: [SidebarBody: Int], applied: Duration,
        changes: Set<String>
    ) {
        self.evaluations.append(evaluations)
        self.mounts.append(mounts)
        self.applied.append(applied)
        self.changes.formUnion(changes)
    }

    func maximum(_ kind: SidebarBody) -> Int { evaluations.map { $0[kind] ?? 0 }.max() ?? 0 }

    func maximumMounts(_ kind: SidebarBody) -> Int { mounts.map { $0[kind] ?? 0 }.max() ?? 0 }
}

// MARK: - Reads

/// What each real sidebar view's body reads, read the same way, through the
/// same configurations and functions the views build.
@MainActor
enum SidebarReads {
    /// A tab row and its parts: its title, icon and place, whether its window
    /// shows it, whether it is selected, whether it may act, and the look it
    /// wears without a page presentation.
    static func tabRow(_ tab: TabStateModel, in context: BrowserSidebarListContext, isSplitGroupMember: Bool) {
        let configuration = BrowserSidebarTabRowConfiguration(
            tab: tab, context: context, isSelected: context.window.shownTabIDs.contains(tab.id),
            isLoaded: context.isLoaded(tab.id), isSplitGroupMember: isSplitGroupMember)
        _ = (tab.displayTitle, tab.placement, tab.folderID, tab.splitGroupID, tab.isAwayFromSavedAddress)
        _ = (tab.emojiIcon, tab.iconMode, configuration.isPromotionSource, configuration.canClose)
        _ = BrowserTabFaviconSubject(tab: tab, image: context.favicons.icon(of: tab.id))
        _ = configuration.isAvailableForDisplay
        _ = context.space.settings.look
        if !isSplitGroupMember { _ = BrowserSidebarSelection.showsSelected(.tab(tab.id), in: context) }
    }

    /// A split row's container and header: which member the window shows,
    /// what a person chose for the split, and whether any member is selected.
    static func splitRow(
        _ groupID: UUID, members: [TabStateModel], in context: BrowserSidebarListContext,
        interaction: BrowserSidebarInteractionState
    ) {
        let configuration = BrowserSidebarSplitGroupRowConfiguration(
            sidebarInteraction: interaction, groupID: groupID, members: members, context: context, followingTabID: nil,
            spacePresentation: nil)
        _ = (configuration.shownTitle, configuration.emojiIcon, configuration.tint, configuration.isPresented)
        _ = (configuration.placement, configuration.folderID, configuration.isAvailableForDisplay)
        _ = members.map { BrowserTabFaviconSubject(tab: $0, image: context.favicons.icon(of: $0.id)) }
        _ = members.map { BrowserSidebarSelection.showsSelected(.tab($0.id), in: context) }
    }

    /// A folder row: its header, whether it is selected or being renamed, its
    /// kept row's bookkeeping, and whether it may act.
    static func folderRow(
        _ folder: FolderStateModel, depth: Int, in context: BrowserSidebarListContext,
        interaction: BrowserSidebarInteractionState, inheritedKeptTabID: UUID? = nil
    ) -> BrowserFolderGroupConfiguration {
        let configuration = BrowserFolderGroupConfiguration(
            sidebarInteraction: interaction, folder: folder, depth: depth, context: context, spacePresentation: nil,
            inheritedKeptTabID: inheritedKeptTabID)
        _ = (folder.title, folder.displaySymbol, folder.displayColor, folder.isCollapsed, folder.location)
        _ = (configuration.displayBranding, configuration.isAvailableForDisplay)
        _ = BrowserSidebarSelection.showsSelected(.folder(folder.id), in: context)
        _ = interaction.editingFolderRequest
        _ = (configuration.shownFolderTabID, configuration.residencyRevision)
        return configuration
    }

    /// A pinned tile: its icon and name, whether its window shows it, whether
    /// it is selected or shaking off a drag, and whether it may act.
    static func tile(_ tab: TabStateModel, in context: BrowserSidebarListContext) {
        _ = context.window.shownTabIDs.contains(tab.id)
        _ = (tab.displayTitle, tab.iconMode, tab.iconTint, tab.emojiIcon, tab.placement)
        _ = (tab.supportsSavedLocationEditing, tab.nativeContent)
        _ = BrowserTabFaviconSubject(tab: tab, image: context.favicons.icon(of: tab.id))
        _ = context.isLoaded(tab.id)
        _ = BrowserSidebarSelection.showsSelected(.tab(tab.id), in: context)
        _ = context.space.settings.look
        _ = context.isCurrent(context.assignment)
        let selection = context.browser.tabMultiSelection
        _ = (selection.pinnedRejectionGeneration, selection.rejectedPinnedIDs)
    }

    /// The seam: whether the saved section keeps a band and whether the
    /// current section holds anything to clear.
    static func seam(in context: BrowserSidebarListContext, isSavedTabsExpanded: Bool) {
        let sidebar = context.space.sidebar
        if isSavedTabsExpanded, !context.capabilities.showsRowDropIndicators {
            _ = sidebar.section(.saved).holdsTabRows
        }
        let current = sidebar.section(.current)
        guard !current.holdsTabRows, !current.isEmpty else { return }
        _ = current.rows.map { context.space.tabIDs(inFolder: $0.id) }
    }
}
