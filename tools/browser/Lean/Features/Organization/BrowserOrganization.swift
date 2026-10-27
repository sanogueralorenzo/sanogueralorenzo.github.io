import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BrowserDragPayload: Codable {
    enum Kind: String, Codable { case tabs, folder }
    let kind: Kind
    let spaceID: UUID
    let ids: [UUID]
    static let type = "dev.leanbrowser.organization"
}

extension BrowserStore {
    var sidebarOrder: [BrowserTab] {
        activeSpace.tabs.filter { $0.placement == .pinned } + activeSpace.tabs.filter { $0.placement == .saved }
            + activeSpace.tabs.filter { $0.placement == .current }
    }
    var recentTabIDs: [UUID] {
        var seen = Set<UUID>()
        return windowState.recentTabs.filter { id in
            guard let (s, _) = tabIndex(id), session.spaces[s].isPrivate == activeSpace.isPrivate else { return false }
            let split = session.spaces[s].splits.first { $0.tabIDs.contains(id) }
            return seen.insert(split?.id ?? id).inserted
        }
    }
    func clickTab(_ id: UUID) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift), let anchor = selectedTab?.id,
            let first = sidebarOrder.firstIndex(where: { $0.id == anchor }),
            let last = sidebarOrder.firstIndex(where: { $0.id == id })
        {
            selectedTabs.formUnion(sidebarOrder[min(first, last)...max(first, last)].map(\.id))
        } else if modifiers.contains(.command) {
            if !selectedTabs.insert(id).inserted { selectedTabs.remove(id) }
        } else {
            selectedTabs = [id]
        }
        selectTab(id, keepingSelection: true)
    }
    func actionTabs(_ id: UUID) -> [UUID] {
        sidebarOrder.filter { selectedTabs.contains(id) ? selectedTabs.contains($0.id) : $0.id == id }.map(\.id)
    }
    func dragProvider(tab id: UUID) -> NSItemProvider {
        isDragging = true
        var ids = actionTabs(id)
        for split in activeSpace.splits where !Set(split.tabIDs).isDisjoint(with: ids) {
            ids += split.tabIDs.filter { !ids.contains($0) }
        }
        let payload = BrowserDragPayload(kind: .tabs, spaceID: activeSpace.id, ids: ids)
        return dragProvider(payload, url: activeSpace.tabs.first(where: { $0.id == id })?.url)
    }
    func dragProvider(folder: UUID) -> NSItemProvider {
        isDragging = true
        return dragProvider(BrowserDragPayload(kind: .folder, spaceID: activeSpace.id, ids: [folder]), url: nil)
    }
    private func dragProvider(_ payload: BrowserDragPayload, url: URL?) -> NSItemProvider {
        let provider = url.map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
        let data = (try? JSONEncoder().encode(payload)) ?? Data()
        provider.registerDataRepresentation(forTypeIdentifier: BrowserDragPayload.type, visibility: .ownProcess) {
            completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
    func acceptDrop(
        _ providers: [NSItemProvider], before: UUID? = nil, folder: UUID? = nil,
        spaceID: UUID? = nil, placement: BrowserTab.Placement? = nil
    ) -> Bool {
        let destination = spaceID ?? activeSpace.id
        let dropFolder =
            folder
            ?? before.flatMap { id in
                session.spaces.first(where: { $0.id == destination })?.tabs.first(where: { $0.id == id })?.folderID
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
        if provider.hasItemConformingToTypeIdentifier(BrowserDragPayload.type) {
            provider.loadDataRepresentation(forTypeIdentifier: BrowserDragPayload.type) { [weak self] data, _ in
                guard let data, data.count < 65536,
                    let payload = try? JSONDecoder().decode(BrowserDragPayload.self, from: data)
                else { return }
                Task { @MainActor in
                    self?.applyDrop(payload, before: before, folder: folder, spaceID: destination, placement: placement)
                    self?.isDragging = false
                }
            }
            return true
        }
        if provider.canLoadObject(ofClass: NSURL.self) {
            provider.loadObject(ofClass: NSURL.self) { [weak self] value, _ in
                guard let url = value as? URL, ["http", "https"].contains(url.scheme ?? "") else { return }
                Task { @MainActor in
                    guard let self else { return }
                    self.selectSpace(destination)
                    _ = self.open(url, placement: placement ?? (folder == nil ? .current : .saved), folderID: folder)
                    self.isDragging = false
                }
            }
            return true
        }
        return false
    }
    private func applyDrop(
        _ payload: BrowserDragPayload, before: UUID?, folder: UUID?, spaceID: UUID, placement: BrowserTab.Placement?
    ) {
        guard let source = session.spaces.first(where: { $0.id == payload.spaceID }),
            session.spaces.contains(where: { $0.id == spaceID })
        else { return }
        if payload.kind == .folder {
            guard let id = payload.ids.first, source.folders.contains(where: { $0.id == id }) else { return }
            if payload.spaceID == spaceID {
                let nested = descendants(id, in: source)
                guard folder != id, folder.map({ !nested.contains($0) }) ?? true else { return }
                let s = spaceIndex(spaceID)
                guard let index = session.spaces[s].folders.firstIndex(where: { $0.id == id }) else { return }
                session.spaces[s].folders[index].parentID = folder
                changed()
            } else {
                moveFolder(id, from: payload.spaceID, to: spaceID)
            }
            return
        }
        let ids = relatedTabIDs(payload.ids).filter { id in source.tabs.contains(where: { $0.id == id }) }
        guard !ids.isEmpty else { return }
        if payload.spaceID != spaceID {
            moveTabs(ids, to: spaceID, folderID: folder, placement: placement)
            return
        }
        let s = spaceIndex(spaceID)
        let target = before.flatMap { id in session.spaces[s].tabs.first { $0.id == id } }
        if let before, ids.contains(before) { return }
        var moved = session.spaces[s].tabs.filter { ids.contains($0.id) }
        session.spaces[s].tabs.removeAll { ids.contains($0.id) }
        for i in moved.indices {
            moved[i].placement = placement ?? target?.placement ?? (folder != nil ? .saved : moved[i].placement)
            moved[i].folderID = moved[i].placement == .pinned ? nil : (folder ?? target?.folderID)
            if moved[i].placement != .current, moved[i].savedURL == nil { moved[i].savedURL = moved[i].url }
        }
        let index =
            before.flatMap { id in session.spaces[s].tabs.firstIndex { $0.id == id } } ?? session.spaces[s].tabs.count
        session.spaces[s].tabs.insert(contentsOf: moved, at: index)
        changed()
    }
    func relatedTabIDs(_ ids: [UUID]) -> [UUID] {
        var result = Set(ids)
        for split in session.spaces.flatMap(\.splits) where !result.isDisjoint(with: split.tabIDs) {
            result.formUnion(split.tabIDs)
        }
        return session.spaces.flatMap(\.tabs).filter { result.contains($0.id) }.map(\.id)
    }
    func placeTabs(_ ids: [UUID], as placement: BrowserTab.Placement, folderID: UUID? = nil) {
        for id in relatedTabIDs(ids) { placeTab(id, as: placement, folderID: folderID) }
    }
    func duplicateTabs(_ ids: [UUID]) {
        for id in ids {
            guard let (s, t) = tabIndex(id) else { continue }
            var tab = session.spaces[s].tabs[t]
            tab.id = UUID()
            session.spaces[s].tabs.insert(tab, at: t + 1)
            selectTab(tab.id)
        }
        changed()
    }
    func moveTabs(_ ids: [UUID], to destination: UUID, folderID: UUID? = nil, placement: BrowserTab.Placement? = nil) {
        let ids = relatedTabIDs(ids)
        Task {
            guard await prepareTabs(ids) else { return }
            let groups = session.spaces.flatMap(\.splits).filter { Set($0.tabIDs).isSubset(of: Set(ids)) }
            guard session.spaces.contains(where: { $0.id == destination }) else { return }
            for id in ids {
                await pages[id]?.captureDocumentState()
                pages[id]?.checkpointNativeState()
            }
            for id in ids {
                guard let (s, t) = tabIndex(id), session.spaces[s].id != destination else { continue }
                let source = session.spaces[s].id
                let affected = owner.contexts.values.filter {
                    $0.selectedTab?.id == id || $0.windowState.tabsBySpace[source] == id
                }
                detachFromSplits(id)
                pages[id]?.checkpointNativeState()
                var tab = session.spaces[s].tabs.remove(at: t)
                tab.folderID = folderID
                tab.placement = placement ?? tab.placement
                if tab.placement == .current { tab.savedURL = nil }
                unload(id)
                session.spaces[spaceIndex(destination)].tabs.append(tab)
                for context in affected {
                    context.setSelectedTab(nil, in: source)
                }
            }
            if let target = session.spaces.firstIndex(where: { $0.id == destination }) {
                session.spaces[target].splits += groups.filter { group in
                    group.tabIDs.allSatisfy { id in session.spaces[target].tabs.contains { $0.id == id } }
                }
            }
            if let first = ids.first { selectTab(first) }
            changed()
        }
    }
    func descendants(_ id: UUID, in space: BrowserSpace) -> Set<UUID> {
        var ids: Set<UUID> = [id]
        while true {
            let more = Set(space.folders.filter { $0.parentID.map { ids.contains($0) } ?? false }.map(\.id))
            let count = ids.count
            ids.formUnion(more)
            if ids.count == count { return ids }
        }
    }
    func moveFolder(_ id: UUID, from source: UUID, to destination: UUID) {
        guard let space = session.spaces.first(where: { $0.id == source }) else { return }
        let folderIDs = descendants(id, in: space)
        let tabs = relatedTabIDs(space.tabs.filter { $0.folderID.map { folderIDs.contains($0) } ?? false }.map(\.id))
        Task {
            guard await prepareTabs(tabs) else { return }
            for id in tabs {
                await pages[id]?.captureDocumentState()
                pages[id]?.checkpointNativeState()
            }
            guard let sourceIndex = session.spaces.firstIndex(where: { $0.id == source }),
                let targetIndex = session.spaces.firstIndex(where: { $0.id == destination })
            else { return }
            let groups = session.spaces[sourceIndex].splits.filter { Set($0.tabIDs).isSubset(of: Set(tabs)) }
            if session.spaces[sourceIndex].folders.contains(where: { folderIDs.contains($0.id) && $0.kind == .github }),
                session.spaces[targetIndex].folders.contains(where: { $0.kind == .github })
            {
                return
            }
            var folders = session.spaces[sourceIndex].folders.filter { folderIDs.contains($0.id) }
            for i in folders.indices where folders[i].id == id { folders[i].parentID = nil }
            let moving = session.spaces[sourceIndex].tabs.filter { tabs.contains($0.id) }
            session.spaces[sourceIndex].folders.removeAll { folderIDs.contains($0.id) }
            session.spaces[sourceIndex].tabs.removeAll { tabs.contains($0.id) }
            for id in tabs {
                detachFromSplits(id)
                unload(id)
            }
            session.spaces[targetIndex].folders += folders
            session.spaces[targetIndex].tabs += moving
            session.spaces[targetIndex].splits += groups
            for context in owner.contexts.values where context.windowState.spaceID == source {
                if let id = context.selectedTab?.id, tabs.contains(id) { context.setSelectedTab(nil, in: source) }
                if let old = context.windowState.tabsBySpace[source], tabs.contains(old) {
                    context.setSelectedTab(nil, in: source)
                }
            }
            selectSpace(destination)
            changed()
        }
    }
}

struct BrowserDropArea: ViewModifier {
    let store: BrowserStore
    var before: UUID?
    var folder: UUID?
    var spaceID: UUID?
    var placement: BrowserTab.Placement?
    @State private var targeted = false
    func body(content: Content) -> some View {
        content.onDrop(of: [BrowserDragPayload.type, UTType.url.identifier], isTargeted: $targeted) { providers in
            store.acceptDrop(providers, before: before, folder: folder, spaceID: spaceID, placement: placement)
        }.overlay {
            if targeted { RoundedRectangle(cornerRadius: 20).stroke(LeanBrandTheme.textDisplay, lineWidth: 1) }
        }
    }
}
