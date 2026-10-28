import AppKit
import Observation
import SwiftUI

@MainActor @Observable
final class BrowserSidebarReorderState {
    struct Row: Equatable {
        let id: UUID
        let section: BrowserSidebarReorderLayout.Section
        let parentItemID: UUID?
        let frame: CGRect
    }
    struct Zone: Equatable {
        let id: UUID
        var frame: CGRect
        let before: UUID?
        let folder: UUID?
        let placement: BrowserTab.Placement?
        let spaceID: UUID
        let allowsAfter: Bool
        var isSpace = false
        var isScrollable = false
        var isNesting = false
        var createsFolder = false
    }
    struct Target: Equatable {
        enum Kind: Equatable {
            case insert(section: BrowserSidebarReorderLayout.Section, before: UUID?)
            case folder(UUID, placement: BrowserTab.Placement)
            case currentFolder(UUID)
            case space
            case split(index: Int)
        }
        let zoneID: UUID
        let spaceID: UUID
        let kind: Kind

        var isPinned: Bool {
            if case .insert(let section, _) = kind { return section.placement == .pinned }
            return false
        }
    }
    struct Lift {
        let rootIDs: Set<UUID>
        let spaceID: UUID
        let height: CGFloat
        var anchorID: UUID?
    }
    private struct ContentGeometry {
        let owner: UUID
        let spaceID: UUID
        let shown: UUID?
        let bounds: CGRect
        let cards: [UUID: CGRect]
        let gap: CGRect?
        let divider: CGFloat
    }
    @ObservationIgnored private var contentGeometry: ContentGeometry?
    private let contentZoneID = UUID()
    @ObservationIgnored private var rows: [UUID: (owner: UUID, row: Row)] = [:]
    @ObservationIgnored private var replacedRows: [UUID: [UUID: Row]] = [:]
    @ObservationIgnored private var zones: [UUID: Zone] = [:]
    @ObservationIgnored private var restingRows: [UUID: Row] = [:]
    @ObservationIgnored private var restingZones: [UUID: Zone] = [:]
    @ObservationIgnored private var scrollViewport: CGRect?
    @ObservationIgnored private var dividerFrame: CGRect?
    @ObservationIgnored private var restingDividerFrame: CGRect?
    @ObservationIgnored private(set) var spaceViewport = CGRect.zero
    private(set) var spaceLayout: BrowserSpaceReorderLayout?
    private(set) var lift: Lift?
    private(set) var target: Target?
    private(set) var layout = BrowserSidebarReorderLayout()

    func register(_ row: Row, owner: UUID) {
        if let previous = rows[row.id], previous.owner != owner {
            replacedRows[row.id, default: [:]][previous.owner] = previous.row
        }
        replacedRows[row.id]?[owner] = nil
        rows[row.id] = (owner, row)
        if lift != nil, restingRows[row.id] == nil { restingRows[row.id] = row }
    }
    func removeRow(_ id: UUID, owner: UUID) {
        defer { if replacedRows[id]?.isEmpty == true { replacedRows[id] = nil } }
        guard rows[id]?.owner == owner else {
            replacedRows[id]?[owner] = nil
            return
        }
        if let (identity, row) = replacedRows[id]?.first {
            rows[id] = (identity, row)
            replacedRows[id]?[identity] = nil
        } else {
            rows[id] = nil
        }
    }
    func register(_ zone: Zone) {
        zones[zone.id] = zone
        if lift != nil, restingZones[zone.id] == nil { restingZones[zone.id] = zone }
    }
    func removeZone(_ id: UUID) { zones[id] = nil }

    func updateScrollViewport(_ frame: CGRect?, in store: BrowserStore) {
        scrollViewport = frame
        if lift != nil { move(to: NSEvent.mouseLocation, in: store) }
    }

    func registerDivider(_ frame: CGRect) { dividerFrame = frame }

    func showsCurrentDivider(in store: BrowserStore, space: BrowserSpace? = nil) -> Bool {
        let space = space ?? store.activeSpace
        if case .split = target?.kind { return true }
        if case .insert(let section, _) = target?.kind, section.placement == .current { return true }
        return space.tabs.contains { $0.placement == .current }
            || space.folders.contains { $0.parentID == nil && $0.placement == .current }
    }

    func updateSpaceViewport(_ frame: CGRect) {
        spaceViewport = frame
        if let pointer = spaceLayout?.pointer { spaceLayout?.update(at: pointer, viewport: frame) }
    }

    func beginSpace(_ source: UUID, in store: BrowserStore) {
        let frames = zones.values.filter(\.isSpace).reduce(into: [UUID: CGRect]()) { $0[$1.spaceID] = $1.frame }
        spaceLayout = BrowserSpaceReorderLayout(sourceID: source, ids: store.session.spaces.map(\.id), frames: frames)
    }

    func spaceContentMoved(by delta: CGFloat) {
        spaceLayout?.contentMoved(by: delta, viewport: spaceViewport)
    }

    func registerContent(
        owner: UUID, spaceID: UUID, shown: UUID?, bounds: CGRect,
        cards: [UUID: CGRect], gap: CGRect?, divider: CGFloat
    ) {
        contentGeometry = ContentGeometry(
            owner: owner, spaceID: spaceID, shown: shown,
            bounds: bounds, cards: cards, gap: gap, divider: divider)
    }
    func removeContent(owner: UUID) {
        if contentGeometry?.owner == owner { contentGeometry = nil }
    }

    func splitProjection(in store: BrowserStore) -> BrowserSplitDropLayout? {
        guard case .split(let index) = target?.kind, let payload = store.owner.sidebarDrag.payload,
            store.canDropSidebarTabsIntoSplit(payload), let shown = store.selectedTab?.id
        else { return nil }
        return BrowserSplitDropLayout(
            ids: store.activeSplit?.tabIDs ?? [shown], incoming: payload.ids,
            fractions: store.activeSplit?.fractions ?? [1], insertionIndex: index)
    }

    func previewRows(in store: BrowserStore) -> [BrowserSidebarDragPreview.Row] {
        guard let id = lift?.anchorID, let root = restingRows[id] else { return [] }
        let space = store.session.spaces.first { $0.id == lift?.spaceID } ?? store.activeSpace
        let folders = Dictionary(uniqueKeysWithValues: space.folders.map { ($0.id, $0) })
        let tabs = Dictionary(uniqueKeysWithValues: space.tabs.map { ($0.id, $0) })
        let groups = Dictionary(uniqueKeysWithValues: space.splits.map { ($0.id, $0) })
        let inside = folders[id].map { store.descendants($0.id, in: space) } ?? []
        let candidates = restingRows.values.filter { row in
            row.id == id
                || (!inside.isEmpty && (inside.contains(row.id) || row.section.folderID.map(inside.contains) == true))
        }
        let shownGroups = Set(candidates.filter { groups[$0.id] != nil }.map(\.id))
        return candidates.sorted { $0.frame.minY < $1.frame.minY }.compactMap { row in
            if row.parentItemID.map(shownGroups.contains) == true { return nil }
            var frame = row.frame.offsetBy(dx: -root.frame.minX, dy: -root.frame.minY)
            let content: BrowserSidebarDragPreview.Row.Content
            if let folder = folders[row.id] {
                let inset: CGFloat =
                    folder.isExpanded || store.sidebarFolders.state(for: folder.id).keptTabID != nil ? 4 : 0
                frame.origin.x += inset
                frame.origin.y += inset
                frame.size.width -= inset * 2
                frame.size.height = SidebarGeometry.rowHeight
                content = .folder(folder)
            } else if let group = groups[row.id] {
                content = .split(group.tabIDs.compactMap { tabs[$0] })
            } else if let tab = tabs[row.id] {
                content = .tab(tab)
            } else {
                return nil
            }
            return BrowserSidebarDragPreview.Row(id: row.id, frame: frame, content: content)
        }
    }

    func previewFrame(in store: BrowserStore) -> CGRect? {
        guard let projection = splitProjection(in: store), let geometry = contentGeometry,
            let window = store.window, let content = window.contentView
        else { return landingFrame(in: store) }
        let frames = BrowserSplitDropLayout.frames(
            fractions: projection.projectedFractions,
            in: geometry.bounds, vertical: store.activeSplit?.direction == .vertical, divider: geometry.divider)
        let incoming = Set(projection.incoming)
        let gap = zip(projection.orderedIDs, frames).filter { incoming.contains($0.0) }
            .reduce(CGRect.null) { $0.union($1.1) }
        return gap.isNull ? nil : window.convertToScreen(content.convert(gap, to: nil))
    }

    func makeLift(_ payload: BrowserDragPayload, in space: BrowserSpace) -> Lift? {
        guard payload.kind != .space else { return nil }
        var roots = Set(payload.folderIDs)
        var tabs = Set(payload.ids)
        for split in space.splits where Set(split.tabIDs).isSubset(of: tabs) {
            roots.insert(split.id)
            tabs.subtract(split.tabIDs)
        }
        roots.formUnion(tabs)
        let frames = roots.compactMap { rows[$0]?.row.frame }
        let sourceID = payload.sourceID ?? payload.folderIDs.first ?? payload.ids.first
        let anchorID =
            sourceID.flatMap { id in
                roots.contains(id) ? id : space.splits.first { $0.tabIDs.contains(id) && roots.contains($0.id) }?.id
            } ?? roots.min { (rows[$0]?.row.frame.minY ?? .infinity) < (rows[$1]?.row.frame.minY ?? .infinity) }
        return Lift(
            rootIDs: roots, spaceID: payload.spaceID,
            height: max(SidebarGeometry.rowHeight, frames.reduce(0) { $0 + $1.height }), anchorID: anchorID)
    }

    func begin(_ lift: Lift, in store: BrowserStore) {
        self.lift = lift
        restingRows = rows.mapValues(\.row)
        restingZones = zones
        restingDividerFrame = dividerFrame
        var next = BrowserSidebarReorderLayout()
        next.sourceSpaceID = lift.spaceID
        next.hiddenIDs = lift.rootIDs
        next.height = lift.height
        next.removedFrames = lift.rootIDs.compactMap { id in
            guard let row = restingRows[id], row.section.placement != .pinned else { return nil }
            return row.frame
        }
        updatePinProjection(&next, in: store)
        layout = next
        installSourceGap(in: store)
    }

    func finish() {
        spaceLayout = nil
        lift = nil
        target = nil
        layout = BrowserSidebarReorderLayout()
        restingRows.removeAll()
        restingZones.removeAll()
    }

    func frame(of id: UUID) -> CGRect? { restingRows[id]?.frame ?? rows[id]?.row.frame }
    func hides(_ id: UUID) -> Bool { lift?.rootIDs.contains(id) == true }

    func isTargetedFolder(_ id: UUID) -> Bool {
        if case .folder(let folder, _) = target?.kind { return folder == id }
        return false
    }

    func isTargetedCurrentTab(_ id: UUID) -> Bool {
        if case .currentFolder(let tab) = target?.kind { return tab == id }
        return false
    }

    func pinnedLayout(in space: BrowserSpace, width: CGFloat) -> BrowserPinnedTabReorderLayout {
        let ids = space.pinnedTabs.map(\.id)
        var lifted = lift?.spaceID == space.id ? lift?.rootIDs ?? [] : []
        for split in space.splits where lifted.contains(split.id) { lifted.formUnion(split.tabIDs) }
        let remaining = ids.filter { !lifted.contains($0) }
        let insertion = target.flatMap { target -> Int? in
            guard target.spaceID == space.id, case .insert(let section, let before) = target.kind,
                section.placement == .pinned
            else { return nil }
            return before.flatMap { remaining.firstIndex(of: $0) } ?? remaining.count
        }
        return BrowserPinnedTabReorderLayout(
            ids: ids, liftedIDs: lifted, insertionIndex: insertion, availableWidth: width)
    }

    /// Like Crest, hit testing uses projected resting measurements rather than
    /// feeding animated measurements back into the insertion calculation.
    func move(to screenPoint: NSPoint, in store: BrowserStore) {
        if store.owner.sidebarDrag.payload?.kind == .space {
            guard let source = store.owner.sidebarDrag.payload?.spaceID else { return }
            if spaceLayout == nil { beginSpace(source, in: store) }
            if let window = store.window, let content = window.contentView, window.frame.contains(screenPoint) {
                let point = content.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
                spaceLayout?.update(at: point, viewport: spaceViewport)
            } else {
                spaceLayout?.update(at: CGPoint(x: -1_000_000, y: -1_000_000), viewport: spaceViewport)
            }
            return
        }
        guard lift != nil, let window = store.window, let content = window.contentView,
            window.frame.contains(screenPoint)
        else {
            setTarget(nil, in: store)
            return
        }
        let point = content.convert(window.convertPoint(fromScreen: screenPoint), from: nil)
        // A Space dot stays reachable even when a tall list gap covers its
        // old vertical interval. Only the visible portion of the rail accepts.
        for zone in restingZones.values where zone.isSpace && store.showsSidebar {
            guard zone.frame.intersection(spaceViewport).contains(point) else { continue }
            let value = Target(zoneID: zone.id, spaceID: zone.spaceID, kind: .space)
            guard store.canPreviewSidebarDrop(value) else { continue }
            setTarget(value, in: store)
            return
        }
        if let target {
            if target.isPinned, let grid = pinGrid(in: store),
                pinnedLayout(in: store.activeSpace, width: grid.width).frame(for: nil, in: grid)?.contains(point)
                    == true
            {
                return
            }
            if let gap = layout.gap, scrollViewport?.contains(point) == true {
                let top =
                    layout.projected(
                        CGRect(x: gap.frame.minX, y: gap.frame.minY, width: gap.frame.width, height: 0),
                        in: target.spaceID
                    )
                    .minY - layout.height
                if CGRect(x: gap.frame.minX, y: top, width: gap.frame.width, height: layout.height).contains(point) {
                    return
                }
            }
        }
        var candidates = restingZones.values.filter { zone in
            guard store.showsSidebar, !zone.isSpace, zone.spaceID == store.activeSpace.id else { return false }
            return projected(zone, in: store).contains(point)
        }.sorted {
            if $0.isNesting != $1.isNesting { return $0.isNesting }
            return $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }
        let sections = restingZones.values.compactMap { zone -> (Zone, CGFloat)? in
            guard store.showsSidebar, !zone.isSpace, !zone.isNesting, zone.before == nil, zone.folder == nil,
                zone.placement != nil, zone.spaceID == store.activeSpace.id
            else { return nil }
            let frame = projected(zone, in: store)
            guard !frame.isNull, point.x >= frame.minX, point.x <= frame.maxX else { return nil }
            let distance = max(frame.minY - point.y, point.y - frame.maxY, 0)
            return distance <= 160 ? (zone, distance) : nil
        }.sorted { $0.1 < $1.1 }
        let directIDs = Set(candidates.map(\.id))
        candidates += sections.map(\.0).filter { !directIDs.contains($0.id) }
        for zone in candidates {
            if zone.createsFolder {
                let next = Target(
                    zoneID: zone.id, spaceID: zone.spaceID, kind: .currentFolder(zone.before!))
                guard store.canPreviewSidebarDrop(next) else { continue }
                setTarget(next, in: store)
                return
            }
            let frame = projected(zone, in: store)
            let tab = store.activeSpace.tabs.first { $0.id == zone.before }
            let folder = store.activeSpace.folders.first { $0.id == zone.before }
            let destinationFolder = store.activeSpace.folders.first { $0.id == zone.folder }
            let placement =
                zone.placement ?? tab?.placement ?? folder?.placement ?? destinationFolder?.placement ?? .saved
            let parent = zone.folder ?? tab?.folderID ?? folder?.parentID
            let after = zone.allowsAfter && (placement == .pinned ? point.x > frame.midX : point.y > frame.midY)
            let before = zone.before.flatMap {
                store.sidebarInsertionTarget(
                    $0, after: after,
                    excluding: Set(
                        (store.owner.sidebarDrag.payload?.ids ?? [])
                            + (store.owner.sidebarDrag.payload?.folderIDs ?? [])))
            }
            let kind: Target.Kind =
                zone.isNesting && zone.folder != nil
                ? .folder(zone.folder!, placement: placement)
                : .insert(section: .init(spaceID: zone.spaceID, placement: placement, folderID: parent), before: before)
            let next = Target(zoneID: zone.id, spaceID: zone.spaceID, kind: kind)
            guard store.canPreviewSidebarDrop(next) else { continue }
            setTarget(next, in: store)
            return
        }
        let onSidebar =
            store.showsSidebar
            && point.x <= store.sidebarWidth + SidebarGeometry.inset * 2 + SidebarGeometry.hoverMargin
        if !onSidebar, let geometry = contentGeometry, geometry.spaceID == store.activeSpace.id,
            geometry.shown == store.selectedTab?.id, geometry.bounds.contains(point),
            let payload = store.owner.sidebarDrag.payload, store.canDropSidebarTabsIntoSplit(payload)
        {
            if case .split = target?.kind, geometry.gap?.contains(point) == true { return }
            let members = Set(store.activeSplit?.tabIDs ?? store.selectedTab.map { [$0.id] } ?? [])
            let frames = geometry.cards.filter { members.contains($0.key) && !payload.ids.contains($0.key) }.map(
                \.value)
            let index = BrowserSplitDropLayout.insertionIndex(
                at: point, frames: frames,
                vertical: store.activeSplit?.direction == .vertical)
            setTarget(
                Target(zoneID: contentZoneID, spaceID: store.activeSpace.id, kind: .split(index: index)), in: store)
            return
        }
        setTarget(nil, in: store)
    }

    func scroll(by delta: CGFloat, in store: BrowserStore) {
        guard lift != nil, delta != 0 else { return }
        restingRows = restingRows.mapValues { row in
            guard row.section.placement != .pinned else { return row }
            return Row(
                id: row.id, section: row.section, parentItemID: row.parentItemID,
                frame: row.frame.offsetBy(dx: 0, dy: delta))
        }
        restingZones = restingZones.mapValues { zone in
            guard zone.isScrollable else { return zone }
            var next = zone
            next.frame = zone.frame.offsetBy(dx: 0, dy: delta)
            return next
        }
        if let lift {
            layout.removedFrames = lift.rootIDs.compactMap { id in
                guard let row = restingRows[id], row.section.placement != .pinned else { return nil }
                return row.frame
            }
        }
        setTarget(target, in: store, force: true)
        move(to: NSEvent.mouseLocation, in: store)
    }

    func landingFrame(in store: BrowserStore) -> CGRect? {
        if let spaceLayout, spaceLayout.destination != nil, let id = spaceLayout.targetID,
            let frame = spaceLayout.frames[id], let window = store.window, let content = window.contentView
        {
            return window.convertToScreen(content.convert(frame, to: nil))
        }
        guard let target, let window = store.window, let content = window.contentView else { return nil }
        let rowID: UUID?
        switch target.kind {
        case .folder(let id, _), .currentFolder(let id): rowID = id
        default: rowID = nil
        }
        if let id = rowID, let row = restingRows[id] {
            return window.convertToScreen(content.convert(layout.projected(row.frame, in: target.spaceID), to: nil))
        }
        let frame: CGRect
        if target.isPinned, let grid = pinGrid(in: store) {
            frame = pinnedLayout(in: store.activeSpace, width: grid.width).frame(for: nil, in: grid) ?? grid
        } else if let gap = layout.gap {
            frame = layout.projected(
                CGRect(x: gap.frame.minX, y: gap.frame.minY, width: gap.frame.width, height: 0), in: target.spaceID
            )
            .offsetBy(dx: 0, dy: -layout.height)
        } else {
            return nil
        }
        let rect = CGRect(
            origin: frame.origin,
            size: CGSize(
                width: frame.width, height: target.isPinned ? SidebarGeometry.rowHeight : layout.height))
        return window.convertToScreen(content.convert(rect, to: nil))
    }

    private func projected(_ zone: Zone, in store: BrowserStore) -> CGRect {
        if zone.placement == .pinned, zone.before == nil, let grid = pinContainer(in: zone.spaceID) {
            var result = grid
            result.size.height = max(8, pinHeight(in: store, width: grid.width))
            return result
        }
        if let id = zone.before, let row = restingRows[id], row.section.placement == .pinned,
            let grid = pinGrid(in: store)
        {
            return pinnedLayout(in: store.activeSpace, width: grid.width).frame(for: id, in: grid) ?? .null
        }
        let holdsGap =
            !zone.isNesting && zone.before == nil
            && (layout.gap.map {
                ($0.section.placement == zone.placement && $0.section.folderID == zone.folder)
                    || (zone.frame.minY < $0.frame.minY && zone.frame.maxY >= $0.frame.minY)
            } ?? false)
        var frame = layout.projected(zone.frame, in: zone.spaceID, containsGap: holdsGap)
        if zone.isNesting { frame = frame.insetBy(dx: 0, dy: frame.height / 4) }
        if zone.before == nil && !zone.isNesting { frame.size.height = max(8, frame.height) }
        guard zone.isScrollable else { return frame }
        return scrollViewport.map { frame.intersection($0) } ?? .null
    }

    private func pinContainer(in spaceID: UUID) -> CGRect? {
        restingZones.values.first { $0.spaceID == spaceID && $0.before == nil && $0.placement == .pinned }?.frame
    }

    private func pinHeight(in store: BrowserStore, width: CGFloat) -> CGFloat {
        let height = pinnedLayout(in: store.activeSpace, width: width).height
        return height > 0 ? height + SidebarGeometry.pinnedTopInset + SidebarGeometry.pinnedBottomInset : 0
    }

    private func pinGrid(in store: BrowserStore) -> CGRect? {
        guard var frame = pinContainer(in: store.activeSpace.id) else { return nil }
        frame.origin.y += SidebarGeometry.pinnedTopInset
        frame.size.height = pinnedLayout(in: store.activeSpace, width: frame.width).height
        return frame
    }

    private func updatePinProjection(_ projection: inout BrowserSidebarReorderLayout, in store: BrowserStore) {
        if let frame = restingDividerFrame {
            projection.dividerFrame = frame
            projection.dividerHeightDelta =
                (showsCurrentDivider(in: store) ? SidebarGeometry.currentDividerHeight : 0) - frame.height
        }
        guard let grid = pinContainer(in: store.activeSpace.id) else { return }
        projection.gridFrame = grid
        projection.gridHeightDelta = pinHeight(in: store, width: grid.width) - grid.height
    }

    private func installSourceGap(in store: BrowserStore) {
        guard let lift, lift.spaceID == store.activeSpace.id, let id = lift.anchorID,
            let row = restingRows[id], let payload = store.owner.sidebarDrag.payload
        else { return }
        let space = store.activeSpace
        let anchor = space.splits.first { $0.id == id }?.tabIDs.first ?? id
        let siblings =
            row.section.placement == .pinned
            ? space.pinnedTabs.map(\.id)
            : space.sidebarEntries(parentID: row.section.folderID, placement: row.section.placement).map(\.id)
        guard let index = siblings.firstIndex(of: anchor) else { return }
        let moving = Set(payload.ids + payload.folderIDs)
        let before = siblings.dropFirst(index + 1).first { !moving.contains($0) }
        guard let zone = restingZones.values.first(where: { $0.before == anchor && !$0.isNesting }) else { return }
        let value = Target(zoneID: zone.id, spaceID: lift.spaceID, kind: .insert(section: row.section, before: before))
        if store.canPreviewSidebarDrop(value) { setTarget(value, in: store) }
    }

    private func setTarget(_ value: Target?, in store: BrowserStore, force: Bool = false) {
        guard force || value != target else { return }
        let motion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : LeanMotion.dragSource
        withAnimation(motion) {
            target = value
            var next = layout
            next.gap = nil
            if let value, case .insert(let section, let before) = value.kind, section.placement != .pinned {
                let candidates = restingRows.values.filter { row in
                    row.section == section && row.parentItemID == section.folderID && !next.hiddenIDs.contains(row.id)
                }.sorted { $0.frame.minY < $1.frame.minY }
                let anchor = before.flatMap { before in
                    let group = store.activeSpace.splits.first { $0.tabIDs.contains(before) }
                    return candidates.first { $0.id == (group?.id ?? before) }
                }
                let last = anchor == nil ? candidates.last : nil
                let frame =
                    anchor?.frame ?? last.map {
                        CGRect(x: $0.frame.minX, y: $0.frame.maxY, width: $0.frame.width, height: 0)
                    } ?? restingZones[value.zoneID].map {
                        CGRect(x: $0.frame.minX, y: $0.frame.maxY, width: $0.frame.width, height: 0)
                    } ?? .zero
                var parents = Set<UUID>()
                var parent = section.folderID
                while let id = parent, parents.insert(id).inserted {
                    parent = store.activeSpace.folders.first { $0.id == id }?.parentID
                }
                next.gap = .init(
                    section: section, before: anchor?.id, after: last?.id, frame: frame, containingFolders: parents)
            }
            updatePinProjection(&next, in: store)
            layout = next
        }
    }
}

extension BrowserStore {
    func canPreviewSidebarDrop(_ target: BrowserSidebarReorderState.Target) -> Bool {
        guard !isClosed, let payload = owner.sidebarDrag.payload, payload.kind != .space,
            let source = session.spaces.first(where: { $0.id == payload.spaceID }),
            let destination = session.spaces.first(where: { $0.id == target.spaceID })
        else { return false }
        let placement: BrowserTab.Placement?
        let parent: UUID?
        let before: UUID?
        switch target.kind {
        case .currentFolder(let id):
            return payload.spaceID == target.spaceID && canCreateCurrentFolder(around: id, from: payload)
        case .insert(let section, let anchor):
            guard section.spaceID == target.spaceID else { return false }
            placement = section.placement
            parent = section.folderID
            before = anchor
        case .folder(let id, let location):
            placement = location
            parent = id
            before = nil
        case .space:
            guard payload.spaceID != target.spaceID else { return false }
            placement = nil
            parent = nil
            before = nil
        case .split: return payload.spaceID == target.spaceID && canDropSidebarTabsIntoSplit(payload)
        }
        let folders = payload.folderIDs.reduce(into: Set<UUID>()) { $0.formUnion(descendants($1, in: source)) }
        let tabs = source.tabs.filter { payload.ids.contains($0.id) || $0.folderID.map(folders.contains) == true }
        let carriesLiveFolder = source.folders.contains { folders.contains($0.id) && $0.kind == .github }
        guard Set(payload.ids).isSubset(of: Set(source.tabs.map(\.id))),
            payload.folderIDs.allSatisfy({ id in source.folders.contains { $0.id == id } }),
            !tabs.isEmpty || !folders.isEmpty,
            !carriesLiveFolder
                || (!destination.isPrivate && placement != .current
                    && !destination.folders.contains { $0.kind == .github && !folders.contains($0.id) }),
            before.map({ !payload.ids.contains($0) && !folders.contains($0) }) ?? true,
            folders.isEmpty || placement != .pinned,
            !tabs.contains(where: { $0.isSettings && (parent != nil || (placement != nil && placement != .current)) }),
            source.id == destination.id || destination.tabs.count + tabs.count <= BrowserSpace.maximumTabCount,
            source.id == destination.id || destination.folders.count + folders.count <= 4096
        else { return false }
        if let folder = parent {
            guard !folders.contains(folder),
                destination.folders.contains(where: {
                    $0.id == folder && $0.kind == .regular && ($0.placement ?? .saved) == placement
                })
            else { return false }
        }
        let moving = source.folders.filter { folders.contains($0.id) }.map { folder in
            var folder = folder
            if payload.folderIDs.contains(folder.id) { folder.parentID = parent }
            return folder
        }
        let byID = Dictionary(
            uniqueKeysWithValues: (destination.folders.filter { !folders.contains($0.id) } + moving).map { ($0.id, $0) }
        )
        for folder in moving {
            var chain = Set([folder.id])
            var parent = folder.parentID
            while let id = parent {
                guard chain.count < 33, chain.insert(id).inserted, let ancestor = byID[id] else { return false }
                parent = ancestor.parentID
            }
        }
        return true
    }
}
