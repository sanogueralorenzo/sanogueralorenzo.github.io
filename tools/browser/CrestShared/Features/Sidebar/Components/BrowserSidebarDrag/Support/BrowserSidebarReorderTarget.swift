import CoreGraphics
import Foundation

// MARK: - Types

/// A drop a target makes of a lift: the core's intent, the Space the window
/// follows the lift to, if any, and whether the lift leaves its Space.
struct BrowserSidebarDrop {
    let intent: any SidebarDrop
    var following: SpaceModel? = nil
    /// Whether the lift leaves the Space it was lifted in, so a selection it
    /// carried is let go rather than kept selected where it landed.
    var leavesSpace = false
}

/// Where a lifted sidebar item will land when released.
struct BrowserSidebarReorderTarget: Equatable, Sendable {
    // MARK: - Types

    enum Kind: Equatable, Sendable {
        /// Insert into an ordered section before `beforeID` (`nil` appends).
        /// `index` is the resolved slot, used to displace neighbours.
        case insert(
            section: BrowserSidebarReorderSection,
            beforeID: BrowserSidebarReorderItemID?,
            index: Int
        )
        /// Land inside a collapsed folder.
        case intoFolder(UUID)
        case createCurrentFolder(UUID)
        /// Move to another space.
        case space(BrowserSpaceRuntimeAssignment)
        /// Join the cards the content area is presenting, as the card at
        /// `index` among them. The index counts presented cards only — the drop
        /// placeholder is not one of them — so it stays put as the row of cards
        /// shifts to make room.
        case splitInsert(assignment: BrowserSpaceRuntimeAssignment, index: Int)

        // MARK: - Actions - Verdicts

        /// What the core says of dropping `plan`'s lift here, from the drop
        /// `targets` it listed as the lift began: whether it may land, the
        /// rule that refuses it, or that the core offers no such target.
        @MainActor
        func verdict(in plan: BrowserSidebarLiftPlan, targets: DropTargetList) -> BrowserSidebarDropVerdict {
            switch self {
            case .insert(let section, _, _):
                return plan.verdict(onList: section.list(in: targets))
            case .intoFolder(let folderID):
                return plan.verdict(onList: targets.lists.first { $0.folderID == folderID })
            case .space(let assignment):
                guard targets.spaceIDs.contains(assignment.spaceID) else { return .unavailable }
                return plan.verdict(onSpace: assignment.spaceID)
            case .splitInsert:
                return BrowserSidebarDropVerdict(targets.split.map { $0.refusal })
            case .createCurrentFolder(let tabID):
                return targets.folderAroundTabIDs.contains(tabID) ? .allowed : .unavailable
            }
        }

        // MARK: - Actions - Dropping

        /// The drop that lands `selection`, lifted in `space` of `browser`'s
        /// window, here: the core's intent, the Space the window follows the
        /// lift to, if any, and whether it leaves its Space; nil where the
        /// target no longer stands.
        @MainActor
        func drop(
            lifting selection: TabSelection, in space: SpaceModel, from browser: BrowserStore
        ) -> BrowserSidebarDrop? {
            let (workspaceID, windowID, spaceID) = (browser.family.workspaceID, browser.windowID, space.id)
            switch self {
            case .insert(let section, let beforeID, _):
                let (placement, folderID) = section.list(in: space)
                return BrowserSidebarDrop(
                    intent: DropIntoList(
                        workspaceID: workspaceID, windowID: windowID, spaceID: spaceID, selection: selection,
                        section: placement, folderID: folderID,
                        beforeTabID: beforeID?.anchorTabID(in: space, lifted: Set(selection.memberTabIDs)),
                        beforeFolderID: beforeID?.folderID)
                )
            case .intoFolder(let folderID):
                guard let folder = space.folders.model(folderID) else { return nil }
                return BrowserSidebarDrop(
                    intent: DropIntoList(
                        workspaceID: workspaceID, windowID: windowID, spaceID: spaceID, selection: selection,
                        section: folder.location, folderID: folderID, beforeTabID: nil, beforeFolderID: nil)
                )
            case .space(let destination):
                guard let destinationSpace = browser.spaceModel(destination.spaceID),
                    destinationSpace.profileID == destination.profileID
                else { return nil }
                let follows = browser.linkPreferences.preferences.followsMovedTabs
                return BrowserSidebarDrop(
                    intent: DropOnSpace(
                        workspaceID: workspaceID, windowID: windowID, spaceID: spaceID, selection: selection,
                        destinationSpaceID: destination.spaceID, follows: follows),
                    following: follows ? destinationSpace : nil,
                    leavesSpace: true
                )
            case .splitInsert(let assignment, let index):
                // The cards on show are the shown tab's split, so the shown tab is
                // the one the lift joins, and a window showing one tab makes a split.
                guard assignment.spaceID == spaceID, let shown = browser.selectedTabID(in: spaceID) else { return nil }
                return BrowserSidebarDrop(
                    intent: DropIntoSplit(
                        workspaceID: workspaceID, windowID: windowID, spaceID: spaceID, selection: selection,
                        targetTabID: shown, index: index)
                )
            case .createCurrentFolder(let tabID):
                return BrowserSidebarDrop(
                    intent: DropAroundTab(
                        workspaceID: workspaceID, windowID: windowID, spaceID: spaceID, selection: selection,
                        tabID: tabID)
                )
            }
        }

        // MARK: - Actions - Presentation

        /// The shape a lifted tab takes over this target, or `resting`, the
        /// shape it keeps where the target says nothing of its own.
        func previewShape(resting: BrowserTabDragPreviewShape?) -> BrowserTabDragPreviewShape? {
            switch self {
            case .insert(let section, _, _): section.restingPreviewShape
            case .intoFolder, .createCurrentFolder: .row
            case .splitInsert: .webpageCard
            case .space: resting
            }
        }

        /// Where a lift released here settles in the sidebar, from the lift's
        /// `layout`, the `pinned` grid's and the registered `rows`; nil where it
        /// leaves the sidebar.
        @MainActor
        func landingFrame(
            layout: BrowserSidebarReorderLayout,
            pinned: @autoclosure () -> (layout: BrowserPinnedTabReorderLayout, frame: CGRect, emptyHeight: CGFloat)?,
            rows: [BrowserSidebarReorderItemID: BrowserSidebarReorderGeometry.RegisteredRow]
        ) -> CGRect? {
            switch self {
            case .insert(let section, _, _):
                if section.usesGridOrdering, let pinned = pinned() {
                    return pinned.layout.frame(for: .gap, in: pinned.frame)
                }
                return layout.gapFrame
            case .intoFolder(let id):
                return rows[.folder(id)].flatMap { layout.frame(for: $0.row) }
            case .createCurrentFolder(let id):
                return rows[.tab(id)].flatMap { layout.frame(for: $0.row) }
            case .space, .splitInsert:
                return nil
            }
        }
    }

    // MARK: - Variables

    let kind: Kind

    var section: BrowserSidebarReorderSection? {
        guard case .insert(let section, _, _) = kind else { return nil }
        return section
    }
}
