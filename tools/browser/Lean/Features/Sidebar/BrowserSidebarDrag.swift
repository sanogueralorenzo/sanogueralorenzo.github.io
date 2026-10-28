import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BrowserDragPayload {
    enum Kind { case tabs, folder, space }
    let kind: Kind
    let spaceID: UUID
    let ids: [UUID]
    var folderIDs: [UUID] = []
    var activeTabID: UUID?
    var sourceID: UUID?
    static let type = UTType(exportedAs: "dev.leanbrowser.organization", conformingTo: .data).identifier
}

extension BrowserStore {
    var sidebarOrder: [BrowserTab] {
        let tabs = Dictionary(uniqueKeysWithValues: activeSpace.tabs.map { ($0.id, $0) })
        return activeSpace.sidebarItemIDs.compactMap { tabs[$0] }
    }
    var recentTabIDs: [UUID] {
        var seen = Set<UUID>()
        return windowState.recentTabs.filter { id in
            guard let (s, _) = tabIndex(id), session.spaces[s].isPrivate == activeSpace.isPrivate else { return false }
            let split = session.spaces[s].splits.first { $0.tabIDs.contains(id) }
            return seen.insert(split?.id ?? id).inserted
        }
    }
    func dragPayload(tab id: UUID) -> BrowserDragPayload {
        let capturesSelection =
            selectionCovers(activeSpace.tabs.first { $0.id == id }?.folderID)
            || (selectedTabs.contains(id) && selectedSidebarItems.count > 1)
        let ids = capturesSelection ? selectedLooseTabIDs : [id]
        return BrowserDragPayload(
            kind: .tabs, spaceID: activeSpace.id, ids: ids,
            folderIDs: capturesSelection ? selectionRootFolders : [], activeTabID: selectedTab?.id, sourceID: id)
    }
    func dragPayload(split: BrowserSplit) -> BrowserDragPayload {
        guard let first = split.tabIDs.first else {
            return BrowserDragPayload(kind: .tabs, spaceID: activeSpace.id, ids: [])
        }
        let selection = dragPayload(tab: first)
        if !selection.folderIDs.isEmpty || selection.ids.count > 1 { return selection }
        return BrowserDragPayload(
            kind: .tabs, spaceID: activeSpace.id, ids: split.tabIDs, activeTabID: selectedTab?.id,
            sourceID: split.id)
    }
    func dragPayload(space id: UUID) -> BrowserDragPayload {
        BrowserDragPayload(kind: .space, spaceID: id, ids: [id])
    }
    func dragPayload(folder: UUID) -> BrowserDragPayload {
        let capturesSelection =
            selectedFolders.contains(folder)
            || selectionCovers(activeSpace.folders.first { $0.id == folder }?.parentID)
        return BrowserDragPayload(
            kind: .folder, spaceID: activeSpace.id,
            ids: capturesSelection ? selectedLooseTabIDs : [],
            folderIDs: capturesSelection ? selectionRootFolders : [folder], activeTabID: selectedTab?.id,
            sourceID: folder)
    }
    func acceptDrop(
        _ providers: [NSItemProvider], before: UUID? = nil, folder: UUID? = nil,
        spaceID: UUID? = nil, placement: BrowserTab.Placement? = nil, afterSpace: Bool = false
    ) -> Bool {
        let destination = spaceID ?? activeSpace.id
        let dropFolder =
            folder
            ?? before.flatMap { id in
                let space = session.spaces.first { $0.id == destination }
                return space?.tabs.first { $0.id == id }?.folderID ?? space?.folders.first { $0.id == id }?.parentID
            }
        if let folder = dropFolder,
            session.spaces.first(where: { $0.id == destination })?.folders.first(where: { $0.id == folder })?.kind
                != .regular
        {
            return false
        }
        guard session.spaces.contains(where: { $0.id == destination }), let provider = providers.first else {
            return false
        }
        if let payload = owner.sidebarDrag {
            let onSpace = spaceID != nil && before == nil && folder == nil && placement == nil
            guard payload.kind != .space || onSpace,
                !onSpace || payload.kind == .space || payload.spaceID != destination
            else { return false }
            return applySidebarDrop(
                payload, before: before, folder: folder, spaceID: destination, placement: placement,
                afterSpace: afterSpace)
        }
        // A foreign process cannot move this session's items by supplying IDs.
        if provider.hasItemConformingToTypeIdentifier(BrowserDragPayload.type) { return false }
        if provider.canLoadObject(ofClass: NSURL.self) {
            guard canChangeTabCount(by: 1, in: destination) else { return false }
            provider.loadObject(ofClass: NSURL.self) { [weak self] value, _ in
                guard let url = value as? URL, ["http", "https"].contains(url.scheme ?? "") else { return }
                Task { @MainActor in
                    guard let self, !self.isClosed,
                        let space = self.session.spaces.first(where: { $0.id == destination }),
                        before.map({ space.orderedSidebarIDs.contains($0) }) ?? true,
                        dropFolder.map({ id in space.folders.contains { $0.id == id && $0.kind == .regular } }) ?? true
                    else { return }
                    guard self.canChangeTabCount(by: 1, in: destination) else { return }
                    self.selectSpace(destination)
                    let target = before.flatMap { id in self.activeSpace.tabs.first { $0.id == id } }
                    guard
                        let id = self.open(
                            url,
                            placement: placement ?? target?.placement ?? dropFolder.flatMap { id in
                                self.activeSpace.folders.first { $0.id == id }?.placement ?? .saved
                            } ?? .current, folderID: dropFolder)
                    else { return }
                    self.reorderSidebarItems([id], in: destination, before: before)
                    self.changed()
                }
            }
            return true
        }
        return false
    }
    func applySidebarDrop(
        _ payload: BrowserDragPayload, before: UUID?, folder: UUID?, spaceID: UUID, placement: BrowserTab.Placement?,
        afterSpace: Bool
    ) -> Bool {
        guard session.spaces.contains(where: { $0.id == payload.spaceID }),
            session.spaces.contains(where: { $0.id == spaceID })
        else { return false }
        if payload.kind == .space {
            return moveSpace(payload.spaceID, relativeTo: spaceID, after: afterSpace)
        }
        let destinationSpace = session.spaces[spaceIndex(spaceID)]
        let beforeFolder = before.flatMap { id in destinationSpace.folders.first { $0.id == id } }
        let beforeTab = before.flatMap { id in destinationSpace.tabs.first { $0.id == id } }
        let destinationParent = folder ?? beforeFolder?.parentID ?? beforeTab?.folderID
        let location =
            placement ?? beforeFolder.map { $0.placement ?? .saved } ?? beforeTab?.placement
            ?? destinationParent.flatMap { id in
                destinationSpace.folders.first { $0.id == id }.map { $0.placement ?? .saved }
            }
        return moveSidebarItems(
            payload, to: spaceID, parentID: destinationParent, placement: location, before: before)
    }

    var canCommitSidebarDrop: Bool {
        guard !isClosed, !owner.sidebarDropCommitted, let payload = owner.sidebarDrag else { return false }
        if payload.kind == .space {
            guard let destination = sidebarReorder.spaceLayout?.destination else { return false }
            return session.spaces.contains { $0.id == payload.spaceID }
                && session.spaces.contains { $0.id == destination.id }
        }
        return sidebarReorder.target.map(canPreviewSidebarDrop) ?? false
    }

    @discardableResult
    func commitSidebarDrop() -> Bool {
        guard canCommitSidebarDrop, let payload = owner.sidebarDrag else { return false }
        let accepted: Bool
        if payload.kind == .space, let destination = sidebarReorder.spaceLayout?.destination {
            accepted = moveSpace(payload.spaceID, relativeTo: destination.id, after: destination.after)
        } else if let target = sidebarReorder.target {
            switch target.kind {
            case .currentFolder(let id):
                accepted = createSidebarFolder(containing: payload, placement: .current, around: id) != nil
            case .insert(let section, let before):
                accepted = applySidebarDrop(
                    payload, before: before, folder: section.folderID,
                    spaceID: target.spaceID, placement: section.placement, afterSpace: false)
            case .folder(let id, let placement):
                accepted = applySidebarDrop(
                    payload, before: nil, folder: id,
                    spaceID: target.spaceID, placement: placement, afterSpace: false)
            case .space:
                accepted = applySidebarDrop(
                    payload, before: nil, folder: nil,
                    spaceID: target.spaceID, placement: nil, afterSpace: false)
            case .split(let index): accepted = dropSidebarTabsIntoSplit(payload, at: index)
            }
        } else {
            return false
        }
        if accepted { owner.sidebarDropCommitted = true }
        return accepted
    }

    func sidebarInsertionTarget(
        _ id: UUID, after: Bool, in spaceID: UUID? = nil, excluding moving: Set<UUID> = []
    ) -> UUID? {
        guard let space = session.spaces.first(where: { $0.id == (spaceID ?? activeSpace.id) }) else { return nil }
        let tab = space.tabs.first { $0.id == id }
        let folder = space.folders.first { $0.id == id }
        guard !moving.contains(id) else { return id }
        let anchor = space.splits.first { $0.tabIDs.contains(id) }?.tabIDs.first { !moving.contains($0) } ?? id
        guard after else { return anchor }
        let siblings: [UUID]
        if tab?.placement == .pinned {
            siblings = space.pinnedTabs.map(\.id)
        } else {
            siblings = space.sidebarEntries(
                parentID: tab?.folderID ?? folder?.parentID,
                placement: tab?.placement ?? folder?.placement ?? .saved
            ).map(\.id)
        }
        let units = siblings.filter { candidate in
            !moving.contains(candidate)
                && !space.splits.contains {
                    $0.tabIDs.contains(candidate) && $0.tabIDs.first(where: { !moving.contains($0) }) != candidate
                }
        }
        guard let index = units.firstIndex(of: anchor) else { return nil }
        return units.dropFirst(index + 1).first { !moving.contains($0) }
    }
}

struct BrowserDropArea: ViewModifier {
    let store: BrowserStore
    var before: UUID?
    var folder: UUID?
    var spaceID: UUID?
    var placement: BrowserTab.Placement?
    var allowsAfter = true
    var isSpaceRail = false
    @State private var targeted = false
    @State private var insertAfter = false
    @State private var nesting = true
    @State private var size = CGSize.zero
    @State private var zoneID = UUID()
    @State private var besideZoneID = UUID()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pinned: Bool {
        before.map { id in store.activeSpace.tabs.contains { $0.id == id && $0.placement == .pinned } } ?? false
    }

    func body(content: Content) -> some View {
        content.onDrop(
            of: [BrowserDragPayload.type, UTType.url.identifier],
            delegate: BrowserSidebarDropDelegate(
                store: store, before: before, folder: folder, spaceID: spaceID, placement: placement,
                targeted: $targeted, insertAfter: $insertAfter, nesting: $nesting, size: size, allowsAfter: allowsAfter,
                reduceMotion: reduceMotion)
        )
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: { frame in
            guard !isSpaceRail else { return }
            store.sidebarReorder.register(
                .init(
                    id: zoneID, frame: frame, before: before, folder: folder, placement: placement,
                    spaceID: spaceID ?? store.activeSpace.id, allowsAfter: allowsAfter,
                    isSpace: spaceID != nil && before == nil && folder == nil && placement == nil,
                    isScrollable: spaceID == nil && placement != .pinned && !pinned,
                    isNesting: folder != nil && before == nil))
            if let folder, before == nil,
                let header = store.activeSpace.folders.first(where: { $0.id == folder })
            {
                store.sidebarReorder.register(
                    .init(
                        id: besideZoneID, frame: frame, before: folder, folder: nil,
                        placement: header.placement ?? .saved, spaceID: store.activeSpace.id,
                        allowsAfter: true, isScrollable: true))
            } else if let before, !pinned {
                store.sidebarReorder.register(
                    .init(
                        id: besideZoneID, frame: frame, before: before, folder: nil,
                        placement: .current, spaceID: spaceID ?? store.activeSpace.id, allowsAfter: false,
                        isScrollable: true, isNesting: true, createsFolder: true))
            }
        }
        .onDisappear {
            store.sidebarReorder.removeZone(zoneID)
            store.sidebarReorder.removeZone(besideZoneID)
        }
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            size = $0
        }
        .onChange(of: store.owner.sidebarDrag != nil) { _, active in
            if !active {
                targeted = false
                insertAfter = false
                nesting = true
            }
        }
        .overlay {
            Group {
                if targeted && store.owner.sidebarLift == nil && store.owner.sidebarDrag?.kind != .space {
                    if before != nil || (folder != nil && !nesting) {
                        Rectangle().fill(LeanBrandTheme.textDisplay)
                            .frame(width: pinned ? 2 : nil, height: pinned ? nil : 2)
                            .frame(
                                maxWidth: .infinity, maxHeight: .infinity,
                                alignment: pinned
                                    ? (insertAfter ? .trailing : .leading) : (insertAfter ? .bottom : .top))
                    } else {
                        RoundedRectangle(cornerRadius: 20).stroke(LeanBrandTheme.textDisplay, lineWidth: 1)
                    }
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .padding(.bottom, emptyGap)
        .overlay(alignment: .bottom) { BrowserSidebarReorderGap(height: emptyGap) }
        .animation(LeanMotion.dragSource.unlessReducingMotion(reduceMotion), value: emptyGap)
    }

    private var emptyGap: CGFloat {
        guard before == nil, folder == nil, spaceID == nil, placement != .pinned else { return 0 }
        return store.sidebarReorder.layout.emptySpace(
            in: .init(
                spaceID: store.activeSpace.id, placement: placement ?? .current, folderID: nil))
    }
}

private struct BrowserSidebarDropDelegate: DropDelegate {
    let store: BrowserStore
    let before: UUID?
    let folder: UUID?
    let spaceID: UUID?
    let placement: BrowserTab.Placement?
    @Binding var targeted: Bool
    @Binding var insertAfter: Bool
    @Binding var nesting: Bool
    let size: CGSize
    let allowsAfter: Bool
    let reduceMotion: Bool

    private var onSpace: Bool { spaceID != nil && before == nil && folder == nil && placement == nil }
    private var targetTab: BrowserTab? { store.activeSpace.tabs.first { $0.id == before } }
    private var targetFolder: BrowserFolder? { store.activeSpace.folders.first { $0.id == before } }

    private func after(_ info: DropInfo) -> Bool {
        allowsAfter
            && (onSpace || targetTab?.placement == .pinned
                ? info.location.x > size.width / 2 : info.location.y > size.height / 2)
    }

    private func nests(_ info: DropInfo) -> Bool {
        folder == nil || (size.height / 4..<size.height * 3 / 4).contains(info.location.y)
    }

    func dropEntered(info: DropInfo) {
        if store.owner.sidebarLift != nil { store.sidebarReorder.move(to: NSEvent.mouseLocation, in: store) }
        insertAfter = after(info)
        nesting = nests(info)
        targeted = true
    }
    func dropExited(info: DropInfo) { targeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        if store.owner.sidebarDrag != nil {
            store.sidebarReorder.move(to: NSEvent.mouseLocation, in: store)
            return DropProposal(operation: store.canCommitSidebarDrop ? .move : .cancel)
        }
        insertAfter = after(info)
        nesting = nests(info)
        return DropProposal(operation: store.owner.sidebarDrag == nil ? .copy : .move)
    }
    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        if store.owner.sidebarDrag != nil {
            return withAnimation(LeanMotion.collection.unlessReducingMotion(reduceMotion)) {
                store.commitSidebarDrop()
            }
        }
        let header = folder.flatMap { id in store.activeSpace.folders.first { $0.id == id } }
        let nesting = nests(info)
        let anchor = before ?? (nesting ? nil : header?.id)
        let parent = nesting ? folder ?? targetTab?.folderID ?? targetFolder?.parentID : header?.parentID
        return withAnimation(LeanMotion.collection.unlessReducingMotion(reduceMotion)) {
            store.acceptDrop(
                info.itemProviders(for: [BrowserDragPayload.type, UTType.url.identifier]),
                before: anchor.flatMap {
                    store.sidebarInsertionTarget(
                        $0, after: after(info), in: spaceID,
                        excluding: Set(
                            (store.owner.sidebarDrag?.ids ?? []) + (store.owner.sidebarDrag?.folderIDs ?? [])))
                },
                folder: parent, spaceID: spaceID,
                placement: placement ?? targetTab?.placement ?? targetFolder.map { $0.placement ?? .saved }
                    ?? header.map { $0.placement ?? .saved },
                afterSpace: onSpace && after(info))
        }
    }
}
