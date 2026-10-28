import CoreGraphics
import Foundation
import Observation

/// Resting measurements for one window; registrations retain their view owner.
@Observable
@MainActor
final class BrowserSidebarReorderGeometry {
    // MARK: - Types

    struct RegisteredRow {
        let owner: UUID
        var row: BrowserSidebarReorderRow
        let scrollRegionID: UUID?
    }

    struct RegisteredZone {
        var zone: BrowserSidebarReorderZone
        let sidebarViewportID: UUID?
        let scrollRegionID: UUID?
    }

    struct SplitCard {
        let owner: UUID
        let space: BrowserSpaceRuntimeAssignment
        let frame: CGRect
    }

    // MARK: - Static Variables

    /// Rows within this vertical distance share a selection line.
    static let selectionLineTolerance: CGFloat = 2

    // MARK: - Variables

    private(set) var selectionRowsRevision = 0
    /// Advances with every change to the rows, so what is worked out from
    /// them can be kept until they change.
    @ObservationIgnored private(set) var rowsRevision = 0
    @ObservationIgnored private(set) var rows: [BrowserSidebarReorderItemID: RegisteredRow] = [:] {
        didSet { rowsRevision &+= 1 }
    }
    /// Registrations a later one replaced while their view was still on
    /// screen, by item and view. A row that moves between lists is two views
    /// for a moment, and the departing one can measure itself again during its
    /// exit, after the arriving one did; when it leaves, the item falls back to
    /// the view that stays instead of losing its frame.
    @ObservationIgnored private var replacedRows: [BrowserSidebarReorderItemID: [UUID: RegisteredRow]] = [:]
    @ObservationIgnored private(set) var zones: [UUID: RegisteredZone] = [:]
    @ObservationIgnored private(set) var scrollRegions: [UUID: CGRect] = [:]
    @ObservationIgnored private(set) var sidebarViewports: [UUID: CGRect] = [:]
    @ObservationIgnored private(set) var splitCards: [UUID: SplitCard] = [:]

    func register(row: BrowserSidebarReorderRow, owner: UUID, scrollRegionID: UUID?) {
        if let current = rows[row.id] {
            if current.owner != owner { replacedRows[row.id, default: [:]][current.owner] = current }
        } else {
            selectionRowsRevision &+= 1
        }
        replacedRows[row.id]?[owner] = nil
        rows[row.id] = RegisteredRow(owner: owner, row: row, scrollRegionID: scrollRegionID)
    }

    /// Forgets `owner`'s registration of the item. When it was the one in
    /// use, the item keeps the registration of a view still showing it, if
    /// any.
    func removeRow(_ id: BrowserSidebarReorderItemID, owner: UUID) {
        defer { if replacedRows[id]?.isEmpty == true { replacedRows[id] = nil } }
        guard rows[id]?.owner == owner else {
            replacedRows[id]?[owner] = nil
            return
        }
        if let remaining = replacedRows[id]?.first?.value {
            replacedRows[id]?[remaining.owner] = nil
            rows[id] = remaining
        } else {
            rows[id] = nil
            selectionRowsRevision &+= 1
        }
    }

    func registeredRows(in space: BrowserSpaceRuntimeAssignment) -> [BrowserSidebarReorderRow] {
        rows.values.map(\.row).filter { $0.space == space && $0.parentItemID == nil }
    }

    /// Range selection includes offscreen rows of expanded lists.
    func selectionRows(in space: BrowserSpaceRuntimeAssignment) -> [BrowserSidebarReorderRow] {
        registeredRows(in: space).sorted {
            if $0.usesGridOrdering != $1.usesGridOrdering { return $0.usesGridOrdering }
            if abs($0.frame.minY - $1.frame.minY) > Self.selectionLineTolerance {
                return $0.frame.minY < $1.frame.minY
            }
            return $0.frame.minX < $1.frame.minX
        }
    }

    func register(
        zone: BrowserSidebarReorderZone, for id: UUID, sidebarViewportID: UUID?, scrollRegionID: UUID?
    ) {
        zones[id] = RegisteredZone(
            zone: zone, sidebarViewportID: sidebarViewportID, scrollRegionID: scrollRegionID)
    }

    func register(sidebarViewport frame: CGRect, for id: UUID) { sidebarViewports[id] = frame }

    func removeSidebarViewport(for id: UUID) {
        sidebarViewports[id] = nil
        zones = zones.filter { $0.value.sidebarViewportID != id }
    }

    func removeZone(for id: UUID) { zones[id] = nil }

    func register(scrollRegionFrame frame: CGRect, for id: UUID) { scrollRegions[id] = frame }

    func removeScrollRegion(for id: UUID) {
        scrollRegions[id] = nil
        let previousCount = rows.count
        rows = rows.filter { $0.value.scrollRegionID != id }
        replacedRows = replacedRows.compactMapValues { views in
            let kept = views.filter { $0.value.scrollRegionID != id }
            return kept.isEmpty ? nil : kept
        }
        if rows.count != previousCount { selectionRowsRevision &+= 1 }
        zones = zones.filter { $0.value.scrollRegionID != id }
    }

    /// Scrolling translates frozen measurements uniformly during a lift.
    func scrollableContentDidMove(in id: UUID, by offsetY: CGFloat) {
        func moved(_ registration: RegisteredRow) -> RegisteredRow {
            var registration = registration
            registration.row = BrowserSidebarReorderRow(
                id: registration.row.id, space: registration.row.space, section: registration.row.section,
                frame: registration.row.frame.offsetBy(dx: 0, dy: offsetY),
                parentItemID: registration.row.parentItemID)
            return registration
        }
        for key in Array(rows.keys) where rows[key]?.scrollRegionID == id {
            guard let registration = rows[key] else { continue }
            rows[key] = moved(registration)
        }
        replacedRows = replacedRows.mapValues { views in
            views.mapValues { $0.scrollRegionID == id ? moved($0) : $0 }
        }
        for key in Array(zones.keys) where zones[key]?.scrollRegionID == id {
            guard var registration = zones[key] else { continue }
            registration.zone.frame = registration.zone.frame.offsetBy(dx: 0, dy: offsetY)
            zones[key] = registration
        }
    }

    func register(
        splitCardFrame frame: CGRect, for tabID: UUID, in space: BrowserSpaceRuntimeAssignment,
        owner: UUID
    ) {
        splitCards[tabID] = SplitCard(owner: owner, space: space, frame: frame)
    }

    func removeSplitCardFrame(for tabID: UUID, owner: UUID) {
        guard splitCards[tabID]?.owner == owner else { return }
        splitCards[tabID] = nil
    }

    func restingZone(for section: BrowserSidebarReorderSection, inColumn frame: CGRect)
        -> BrowserSidebarReorderZone?
    {
        let target = BrowserSidebarReorderZone.Target.section(section)
        let matching = zones.values.map(\.zone).filter { zone in
            zone.target == target && zone.frame.maxX > frame.minX && zone.frame.minX < frame.maxX
        }
        return matching.min { $0.frame.height < $1.frame.height }
    }
}
