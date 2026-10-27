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
            folderIDs: capturesSelection ? selectionRootFolders : [], activeTabID: selectedTab?.id)
    }
    func dragPayload(split: BrowserSplit) -> BrowserDragPayload {
        guard let first = split.tabIDs.first else {
            return BrowserDragPayload(kind: .tabs, spaceID: activeSpace.id, ids: [])
        }
        let selection = dragPayload(tab: first)
        if !selection.folderIDs.isEmpty || selection.ids.count > 1 { return selection }
        return BrowserDragPayload(kind: .tabs, spaceID: activeSpace.id, ids: split.tabIDs, activeTabID: selectedTab?.id)
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
            folderIDs: capturesSelection ? selectionRootFolders : [folder], activeTabID: selectedTab?.id)
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
            return applyDrop(
                payload, before: before, folder: folder, spaceID: destination, placement: placement,
                afterSpace: afterSpace)
        }
        // A foreign process cannot move this session's items by supplying IDs.
        if provider.hasItemConformingToTypeIdentifier(BrowserDragPayload.type) { return false }
        if provider.canLoadObject(ofClass: NSURL.self) {
            provider.loadObject(ofClass: NSURL.self) { [weak self] value, _ in
                guard let url = value as? URL, ["http", "https"].contains(url.scheme ?? "") else { return }
                Task { @MainActor in
                    guard let self, !self.isClosed,
                        let space = self.session.spaces.first(where: { $0.id == destination }),
                        before.map({ space.orderedSidebarIDs.contains($0) }) ?? true,
                        dropFolder.map({ id in space.folders.contains { $0.id == id && $0.kind == .regular } }) ?? true
                    else { return }
                    self.selectSpace(destination)
                    let target = before.flatMap { id in self.activeSpace.tabs.first { $0.id == id } }
                    let id = self.open(
                        url,
                        placement: placement ?? target?.placement ?? dropFolder.flatMap { id in
                            self.activeSpace.folders.first { $0.id == id }?.placement ?? .saved
                        } ?? .current, folderID: dropFolder)
                    self.reorderSidebarItems([id], in: destination, before: before)
                    self.changed()
                }
            }
            return true
        }
        return false
    }
    private func applyDrop(
        _ payload: BrowserDragPayload, before: UUID?, folder: UUID?, spaceID: UUID, placement: BrowserTab.Placement?,
        afterSpace: Bool
    ) -> Bool {
        guard session.spaces.contains(where: { $0.id == payload.spaceID }),
            session.spaces.contains(where: { $0.id == spaceID })
        else { return false }
        if payload.kind == .space {
            guard payload.spaceID != spaceID,
                let index = session.spaces.firstIndex(where: { $0.id == payload.spaceID })
            else { return false }
            let moving = session.spaces.remove(at: index)
            let target = session.spaces.firstIndex { $0.id == spaceID } ?? session.spaces.count
            session.spaces.insert(moving, at: min(session.spaces.count, target + (afterSpace ? 1 : 0)))
            changed()
            return true
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
    @State private var targeted = false
    @State private var insertAfter = false
    @State private var size = CGSize.zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var pinned: Bool {
        before.map { id in store.activeSpace.tabs.contains { $0.id == id && $0.placement == .pinned } } ?? false
    }

    func body(content: Content) -> some View {
        content.onDrop(
            of: [BrowserDragPayload.type, UTType.url.identifier],
            delegate: BrowserSidebarDropDelegate(
                store: store, before: before, folder: folder, spaceID: spaceID, placement: placement,
                targeted: $targeted, insertAfter: $insertAfter, size: size, allowsAfter: allowsAfter,
                reduceMotion: reduceMotion)
        )
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            size = $0
        }
        .onChange(of: store.owner.sidebarDrag != nil) { _, active in
            if !active {
                targeted = false
                insertAfter = false
            }
        }
        .overlay {
            Group {
                if targeted {
                    if before != nil {
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

    func dropEntered(info: DropInfo) {
        insertAfter = after(info)
        targeted = true
    }
    func dropExited(info: DropInfo) { targeted = false }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        insertAfter = after(info)
        return DropProposal(operation: store.owner.sidebarDrag == nil ? .copy : .move)
    }
    func performDrop(info: DropInfo) -> Bool {
        targeted = false
        return withAnimation(reduceMotion ? nil : .smooth(duration: 0.24)) {
            store.acceptDrop(
                info.itemProviders(for: [BrowserDragPayload.type, UTType.url.identifier]),
                before: before.flatMap {
                    store.sidebarInsertionTarget(
                        $0, after: after(info), in: spaceID,
                        excluding: Set(
                            (store.owner.sidebarDrag?.ids ?? []) + (store.owner.sidebarDrag?.folderIDs ?? [])))
                },
                folder: folder ?? targetTab?.folderID ?? targetFolder?.parentID, spaceID: spaceID,
                placement: placement ?? targetTab?.placement ?? targetFolder.map { $0.placement ?? .saved },
                afterSpace: onSpace && after(info))
        }
    }
}
