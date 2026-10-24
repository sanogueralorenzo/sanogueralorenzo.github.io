import CoreGraphics
import Foundation

/// A measured region that can accept a lifted sidebar item. Zones are ranked by
/// specificity so a folder header or space segment layered inside a section wins
/// over the section behind it.
struct BrowserSidebarReorderZone: Equatable, Sendable {
    // MARK: - Types

    enum Target: Hashable, Sendable {
        /// An ordered run of rows.
        case section(BrowserSidebarReorderSection)
        /// A collapsed folder row: dropping lands the item inside the folder.
        case folder(UUID)
        /// An open tab at the top level: dropping makes a folder around it.
        case currentTab(UUID)
        /// A space picker segment: dropping moves the item to that space.
        case space(BrowserSpaceRuntimeAssignment)
        /// The window's web-content area for a Space: dropping a tab there adds
        /// it to the cards already on show.
        case splitContent(BrowserSpaceRuntimeAssignment)

        // MARK: - Variables

        /// Whether the target files what lands on it inside its own row: a
        /// collapsed folder, or an open tab a folder is made around. It claims
        /// only the middle of its row, so the edges stay available for
        /// reordering past it, and it wins over the section behind it.
        var nests: Bool {
            switch self {
            case .folder, .currentTab: true
            case .section, .space, .splitContent: false
            }
        }

        /// Whether a lift over the target lands there even where an open gap
        /// would hold it in place. A Space picker remains reachable when a tall
        /// batch's temporary gap overlaps it or the lifted folder's moving edge
        /// extends beyond it.
        var outranksGap: Bool {
            switch self {
            case .space: true
            case .section, .folder, .currentTab, .splitContent: false
            }
        }

        // MARK: - Actions - Offers

        /// Whether the core lists a drop on this target among `targets`,
        /// refused or not.
        func isOffered(by targets: DropTargetList) -> Bool {
            switch self {
            case .section(.tabs(let placement, let folderID)):
                targets.lists.contains { $0.section == placement && $0.folderID == folderID }
            case .section(.folders(let parentID)):
                targets.lists.contains { $0.folderID == parentID }
            case .folder(let folderID):
                targets.lists.contains { $0.folderID == folderID }
            case .currentTab(let tabID):
                targets.folderAroundTabIDs.contains(tabID)
            case .space(let assignment):
                targets.spaceIDs.contains(assignment.spaceID)
            case .splitContent:
                targets.split.map { $0.refusal == nil } ?? false
            }
        }

        /// Whether the target takes `item` at all. A section only takes its own
        /// kind of row. Nested groups register a section per kind over the same
        /// frame, so filtering by acceptance before ranking is what stops a
        /// folder resolving against the tab section it overlaps.
        func accepts(_ item: BrowserSidebarReorderItem) -> Bool {
            switch self {
            case .section(let section): item.isAccepted(by: section)
            case .currentTab(let tabID): item.foldsAround(tabID)
            case .folder, .space: true
            case .splitContent(let assignment): item.joinsCards(shownIn: assignment)
            }
        }

        // MARK: - Actions - Landing

        /// Where a lift aimed at this target lands, as `aim` reads the
        /// rows and cards around it, or nil where it lands nowhere.
        @MainActor
        func reorderTarget(for aim: BrowserSidebarReorderAim) -> BrowserSidebarReorderTarget? {
            switch self {
            case .currentTab(let tabID):
                BrowserSidebarReorderTarget(kind: .createCurrentFolder(tabID))
            case .space(let assignment):
                BrowserSidebarReorderTarget(kind: .space(assignment))
            case .folder(let folderID):
                aim.lift.item.id == .folder(folderID)
                    ? nil : BrowserSidebarReorderTarget(kind: .intoFolder(folderID))
            case .section(let section):
                aim.insertionTarget(in: section)
            case .splitContent(let assignment):
                aim.splitInsertTarget(in: assignment)
            }
        }

        /// Where the target measured at `frame` stands in `layout` while a
        /// lift is in flight, or nil while the lift hides it.
        func frame(_ frame: CGRect, in layout: BrowserSidebarReorderLayout) -> CGRect? {
            switch self {
            case .space, .splitContent:
                return frame
            case .folder(let id):
                guard !layout.hiddenIDs.contains(.folder(id)) else { return nil }
                return layout.projected(frame, containsGap: false)
            case .currentTab(let id):
                guard !layout.hiddenIDs.contains(.tab(id)) else { return nil }
                return layout.projected(frame, containsGap: false)
            case .section(let section):
                guard !section.usesGridOrdering else { return frame }
                if let parent = section.parentFolderID, layout.hiddenIDs.contains(.folder(parent)) { return nil }
                return layout.projected(frame, containsGap: layout.holdsGap(section, at: frame))
            }
        }
    }

    // MARK: - Static Variables

    /// How far past a section's edge the pointer may stray and still target it.
    /// Sections wrap their rows tightly, so appending to the end of a list means
    /// dragging into the empty space just below the final row.
    static let slop: CGFloat = 160

    /// Fraction of a collapsed folder's row that nests rather than reorders.
    ///
    /// Dropping onto the middle of the row puts the item inside the folder; the
    /// top and bottom edges belong to the surrounding section, so a row can still
    /// be dragged *past* a collapsed folder instead of always falling into it.
    static let folderNestBand: CGFloat = 0.5

    // MARK: - Variables

    let target: Target
    var frame: CGRect
    var minimumHeight: CGFloat = 0
    var supportsTouch = false

    /// Higher wins when zones overlap.
    ///
    /// The content area sits at zero, below every sidebar zone. It is the
    /// largest zone in the window and the only one a floating sidebar can be
    /// drawn on top of, so it must never outrank a list the pointer is
    /// genuinely inside.
    var specificity: Int {
        switch target {
        case .space: 3
        case .folder, .currentTab: 2
        case .section: 1
        case .splitContent: 0
        }
    }

    /// Whether this is the window's content area — the one zone a sidebar can be
    /// drawn on top of, and the only one whose frame says nothing about what the
    /// pointer is aiming at while it is.
    var isContentArea: Bool {
        switch target {
        case .splitContent: true
        case .section, .folder, .currentTab, .space: false
        }
    }

    /// Breaks ties between zones of equal specificity: a run nested inside
    /// another wins even when the two measure the same rectangle. Only sections
    /// nest; every other target is a leaf.
    var nestingDepth: Int {
        switch target {
        case .section(let section): section.nestingDepth
        case .folder, .currentTab, .space, .splitContent: 0
        }
    }

    private var area: CGFloat {
        frame.width * frame.height
    }

    // MARK: - Actions - Aiming

    /// The middle of a row a nesting target claims, leaving its edges to the
    /// section around it.
    static func nestingFrame(for frame: CGRect) -> CGRect {
        frame.insetBy(dx: 0, dy: frame.height * (1 - folderNestBand) / 2)
    }

    /// The zone the pointer aims `item` at. Only zones the item's kind takes
    /// compete, and of those, only the ones the lift's plan says the core
    /// offers a drop for, so a target the core has no drop for never hides
    /// the section behind it.
    static func aimed(
        at point: CGPoint,
        in zones: [BrowserSidebarReorderZone],
        accepting item: BrowserSidebarReorderItem,
        plan: BrowserSidebarLiftPlan? = nil
    ) -> BrowserSidebarReorderZone? {
        let usable = zones.filter { $0.target.accepts(item) && plan?.offers($0.target) != false }
        let containing = usable.filter { $0.aimingFrame.contains(point) }
        let innermost = containing.max { $0.isLessSpecific(than: $1) }
        if let innermost, !innermost.isContentArea {
            return innermost
        }
        // Containing the pointer is not enough for the content area to own it.
        // A floating sidebar is drawn on top of that zone, so the whole card —
        // including every seam its own layout leaves between the runs, and the
        // furniture above them — sits inside it. Ranking by specificity alone
        // hands those seams to the page: the pinned grid stops being reachable
        // from anywhere but its exact rectangle, which for a grid nobody has
        // filled is a band a few points tall, and a drag that the content area
        // then declines resolves nowhere at all.
        //
        // So a run the pointer is aiming at is offered first, on the same terms
        // as anywhere else in the sidebar — its own column, within the slop that
        // lets a list be appended to. Past the sidebar no run answers, and the
        // page is what is left.
        return nearestSection(to: point, in: usable) ?? innermost
    }

    /// Falls back to the closest section in the same column, so overshooting the
    /// bottom of a list still appends to it instead of cancelling the drop.
    private static func nearestSection(
        to point: CGPoint,
        in zones: [BrowserSidebarReorderZone]
    ) -> BrowserSidebarReorderZone? {
        let sections = zones.filter { zone in
            guard case .section = zone.target else { return false }
            return point.x >= zone.frame.minX && point.x <= zone.frame.maxX
        }
        let reachable = sections.compactMap { zone -> (BrowserSidebarReorderZone, CGFloat)? in
            let distance = zone.verticalDistance(from: point)
            guard distance <= slop else { return nil }
            return (zone, distance)
        }
        // Overlapping runs are the same distance away, so the fallback settles
        // the draw exactly as containment would rather than at random.
        return reachable.min { lhs, rhs in
            lhs.1 == rhs.1 ? rhs.0.isLessSpecific(than: lhs.0) : lhs.1 < rhs.1
        }?.0
    }

    /// The frame that owns the pointer. A folder owns its contents, while its
    /// outer edge belongs to its parent. This makes a seam between siblings
    /// usable.
    private var aimingFrame: CGRect {
        guard case .section(let section) = target, section.parentFolderID != nil else { return frame }
        return frame.insetBy(dx: 0, dy: min(8, frame.height / 4))
    }

    /// Ranks overlapping zones: more specific first, then the more deeply
    /// nested, then the innermost, so a nested folder group wins over the
    /// section that contains it.
    ///
    /// Nesting is ranked before area because the two are not the same question.
    /// A saved list holding one folder and no unfiled rows measures exactly what
    /// the folder group measures, which leaves area a tie — and a tie is settled
    /// by whichever registration the registry happens to yield first, so the
    /// list can end up owning the rows nested inside it. Those rows then belong
    /// to a section with nothing registered in it: no step-aside, no insertion
    /// line, and a drop that quietly unfiles the tab.
    private func isLessSpecific(than other: BrowserSidebarReorderZone) -> Bool {
        if specificity != other.specificity {
            return specificity < other.specificity
        }
        if nestingDepth != other.nestingDepth {
            return nestingDepth < other.nestingDepth
        }
        return area > other.area
    }

    private func verticalDistance(from point: CGPoint) -> CGFloat {
        if point.y < frame.minY { return frame.minY - point.y }
        if point.y > frame.maxY { return point.y - frame.maxY }
        return 0
    }
}
