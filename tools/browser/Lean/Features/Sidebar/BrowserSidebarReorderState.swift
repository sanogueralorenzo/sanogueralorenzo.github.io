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
        let zoneID: UUID
        let before: UUID?
        let folder: UUID?
        let placement: BrowserTab.Placement
        let spaceID: UUID
        var aroundTabID: UUID?
    }
    struct Lift {
        let rootIDs: Set<UUID>
        let spaceID: UUID
        let height: CGFloat
    }
    @ObservationIgnored private var rows: [UUID: (owner: UUID, row: Row)] = [:]
    @ObservationIgnored private var replacedRows: [UUID: [UUID: Row]] = [:]
    @ObservationIgnored private var zones: [UUID: Zone] = [:]
    @ObservationIgnored private var restingRows: [UUID: Row] = [:]
    @ObservationIgnored private var restingZones: [UUID: Zone] = [:]
    @ObservationIgnored private var scrollViewport: CGRect?
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
        return Lift(
            rootIDs: roots, spaceID: payload.spaceID,
            height: max(SidebarGeometry.rowHeight, frames.reduce(0) { $0 + $1.height }))
    }

    func begin(_ lift: Lift, in store: BrowserStore) {
        self.lift = lift
        restingRows = rows.mapValues(\.row)
        restingZones = zones
        var next = BrowserSidebarReorderLayout()
        next.sourceSpaceID = lift.spaceID
        next.hiddenIDs = lift.rootIDs
        next.height = lift.height
        next.removedFrames = lift.rootIDs.compactMap { id in
            guard let row = restingRows[id], row.section.placement != .pinned else { return nil }
            return row.frame
        }
        if let grid = pinGrid(in: store.activeSpace.id) {
            next.gridFrame = grid
            next.gridHeightDelta = pinnedLayout(in: store.activeSpace, width: grid.width).height - grid.height
        }
        layout = next
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
        guard let target, target.folder == id else { return false }
        return restingZones[target.zoneID]?.isNesting == true
    }

    func isTargetedCurrentTab(_ id: UUID) -> Bool { target?.aroundTabID == id }

    func pinnedLayout(in space: BrowserSpace, width: CGFloat) -> BrowserPinnedTabReorderLayout {
        let ids = space.pinnedTabs.map(\.id)
        var lifted = lift?.spaceID == space.id ? lift?.rootIDs ?? [] : []
        for split in space.splits where lifted.contains(split.id) { lifted.formUnion(split.tabIDs) }
        let remaining = ids.filter { !lifted.contains($0) }
        let insertion = target.flatMap { target -> Int? in
            guard target.spaceID == space.id, target.placement == .pinned else { return nil }
            return target.before.flatMap { remaining.firstIndex(of: $0) } ?? remaining.count
        }
        return BrowserPinnedTabReorderLayout(
            ids: ids, liftedIDs: lifted, insertionIndex: insertion, availableWidth: width,
            minimumHeight: lift == nil ? 0 : SidebarGeometry.rowHeight)
    }

    /// Like Crest, hit testing uses projected resting measurements rather than
    /// feeding animated measurements back into the insertion calculation.
    func move(to screenPoint: NSPoint, in store: BrowserStore) {
        if store.owner.sidebarDrag?.kind == .space {
            guard let source = store.owner.sidebarDrag?.spaceID else { return }
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
        if let target {
            if target.placement == .pinned, let grid = pinGrid(in: target.spaceID),
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
        let candidates = restingZones.values.filter { zone in
            guard !zone.isSpace, zone.spaceID == store.activeSpace.id else { return false }
            return projected(zone, in: store).contains(point)
        }.sorted {
            if $0.isNesting != $1.isNesting { return $0.isNesting }
            return $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
        }
        for zone in candidates {
            if zone.createsFolder {
                let next = Target(
                    zoneID: zone.id, before: nil, folder: nil, placement: .current,
                    spaceID: zone.spaceID, aroundTabID: zone.before)
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
                    excluding: Set((store.owner.sidebarDrag?.ids ?? []) + (store.owner.sidebarDrag?.folderIDs ?? [])))
            }
            let next = Target(
                zoneID: zone.id, before: before, folder: parent, placement: placement, spaceID: zone.spaceID)
            guard store.canPreviewSidebarDrop(next) else { continue }
            setTarget(next, in: store)
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
        setTarget(nil, in: store)
        move(to: NSEvent.mouseLocation, in: store)
    }

    func landingFrame(in store: BrowserStore) -> CGRect? {
        if let spaceLayout, spaceLayout.destination != nil, let id = spaceLayout.targetID,
            let frame = spaceLayout.frames[id], let window = store.window, let content = window.contentView
        {
            return window.convertToScreen(content.convert(frame, to: nil))
        }
        guard let target, let window = store.window, let content = window.contentView else { return nil }
        if let id = target.aroundTabID, let row = restingRows[id] {
            return window.convertToScreen(content.convert(layout.projected(row.frame, in: target.spaceID), to: nil))
        }
        let frame: CGRect
        if target.placement == .pinned, let grid = pinGrid(in: target.spaceID) {
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
                width: frame.width, height: target.placement == .pinned ? SidebarGeometry.rowHeight : layout.height))
        return window.convertToScreen(content.convert(rect, to: nil))
    }

    private func projected(_ zone: Zone, in store: BrowserStore) -> CGRect {
        if let id = zone.before, let row = restingRows[id], row.section.placement == .pinned,
            let grid = pinGrid(in: store.activeSpace.id)
        {
            return pinnedLayout(in: store.activeSpace, width: grid.width).frame(for: id, in: grid) ?? .zero
        }
        var frame = layout.projected(
            zone.frame, in: zone.spaceID,
            containsGap: zone.folder.map {
                !zone.isNesting && layout.gap?.containingFolders.contains($0) == true
            } ?? false)
        if zone.isNesting { frame = frame.insetBy(dx: 0, dy: frame.height / 4) }
        // Crest clips projected rows to their scroll viewport; frozen frames
        // may otherwise reach behind fixed Pins and toolbar controls.
        guard zone.isScrollable else { return frame }
        return scrollViewport.map { frame.intersection($0) } ?? .null
    }

    private func pinGrid(in spaceID: UUID) -> CGRect? {
        restingZones.values.first { $0.spaceID == spaceID && $0.before == nil && $0.placement == .pinned }?.frame
    }

    private func setTarget(_ value: Target?, in store: BrowserStore) {
        guard value != target else { return }
        let motion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : LeanMotion.dragSource
        withAnimation(motion) {
            target = value
            var next = layout
            next.gap = nil
            if let value, value.placement != .pinned, value.aroundTabID == nil {
                let section = BrowserSidebarReorderLayout.Section(
                    spaceID: value.spaceID, placement: value.placement, folderID: value.folder)
                let candidates = restingRows.values.filter { row in
                    row.section == section && row.parentItemID == value.folder && !next.hiddenIDs.contains(row.id)
                }.sorted { $0.frame.minY < $1.frame.minY }
                let anchor = value.before.flatMap { before in
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
                var parent = value.folder
                while let id = parent, parents.insert(id).inserted {
                    parent = store.activeSpace.folders.first { $0.id == id }?.parentID
                }
                next.gap = .init(
                    section: section, before: anchor?.id, after: last?.id, frame: frame, containingFolders: parents)
            }
            if let grid = pinGrid(in: store.activeSpace.id) {
                let pins = pinnedLayout(in: store.activeSpace, width: grid.width)
                next.gridFrame = grid
                next.gridHeightDelta = pins.height - grid.height
            }
            layout = next
        }
    }
}

extension BrowserStore {
    func canPreviewSidebarDrop(_ target: BrowserSidebarReorderState.Target) -> Bool {
        guard !isClosed, let payload = owner.sidebarDrag, payload.kind != .space,
            let source = session.spaces.first(where: { $0.id == payload.spaceID }),
            let destination = session.spaces.first(where: { $0.id == target.spaceID })
        else { return false }
        if let id = target.aroundTabID {
            return payload.spaceID == target.spaceID && canCreateCurrentFolder(around: id, from: payload)
        }
        let folders = payload.folderIDs.reduce(into: Set<UUID>()) { $0.formUnion(descendants($1, in: source)) }
        let tabs = source.tabs.filter { payload.ids.contains($0.id) || $0.folderID.map(folders.contains) == true }
        let carriesLiveFolder = source.folders.contains { folders.contains($0.id) && $0.kind == .github }
        guard Set(payload.ids).isSubset(of: Set(source.tabs.map(\.id))),
            payload.folderIDs.allSatisfy({ id in source.folders.contains { $0.id == id } }),
            !tabs.isEmpty || !folders.isEmpty,
            !carriesLiveFolder
                || (!destination.isPrivate && target.placement != .current
                    && !destination.folders.contains { $0.kind == .github && !folders.contains($0.id) }),
            target.before.map({ !payload.ids.contains($0) && !folders.contains($0) }) ?? true,
            folders.isEmpty || target.placement != .pinned,
            !tabs.contains(where: { $0.isSettings && (target.folder != nil || target.placement != .current) }),
            source.id == destination.id || destination.tabs.count + tabs.count <= BrowserSpace.maximumTabCount,
            source.id == destination.id || destination.folders.count + folders.count <= 4096
        else { return false }
        if let folder = target.folder {
            guard !folders.contains(folder),
                destination.folders.contains(where: {
                    $0.id == folder && $0.kind == .regular && ($0.placement ?? .saved) == target.placement
                })
            else { return false }
        }
        let moving = source.folders.filter { folders.contains($0.id) }.map { folder in
            var folder = folder
            if payload.folderIDs.contains(folder.id) { folder.parentID = target.folder }
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
