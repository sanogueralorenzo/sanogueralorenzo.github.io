import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BrowserDragPayload: Codable {
    enum Kind: String, Codable { case tabs, folder, space }
    let kind: Kind
    let spaceID: UUID
    let ids: [UUID]
    var folderIDs: [UUID] = []
    static let type = "dev.leanbrowser.organization"
}

extension BrowserStore {
    var sidebarOrder: [BrowserTab] {
        var result = activeSpace.tabs.filter { $0.placement == .pinned }
        func append(_ parent: UUID?, _ placement: BrowserTab.Placement) {
            for entry in activeSpace.sidebarEntries(parentID: parent, placement: placement) {
                switch entry.kind {
                case .folder(let folder): append(folder.id, placement)
                case .tab(let tab): result.append(tab)
                }
            }
        }
        append(nil, .saved)
        append(nil, .current)
        return result
    }
    var recentTabIDs: [UUID] {
        var seen = Set<UUID>()
        return windowState.recentTabs.filter { id in
            guard let (s, _) = tabIndex(id), session.spaces[s].isPrivate == activeSpace.isPrivate else { return false }
            let split = session.spaces[s].splits.first { $0.tabIDs.contains(id) }
            return seen.insert(split?.id ?? id).inserted
        }
    }
    func dragProvider(tab id: UUID) -> NSItemProvider {
        isDragging = true
        var ids = selectedTabs.contains(id) ? selectedLooseTabIDs : actionTabs(id)
        for split in activeSpace.splits where !Set(split.tabIDs).isDisjoint(with: ids) {
            ids += split.tabIDs.filter { !ids.contains($0) }
        }
        let payload = BrowserDragPayload(
            kind: .tabs, spaceID: activeSpace.id, ids: ids,
            folderIDs: selectedTabs.contains(id) ? selectionRootFolders : [])
        return dragProvider(payload, url: activeSpace.tabs.first(where: { $0.id == id })?.url)
    }
    func dragProvider(space id: UUID) -> NSItemProvider {
        isDragging = true
        return dragProvider(BrowserDragPayload(kind: .space, spaceID: id, ids: [id]), url: nil)
    }
    func dragProvider(folder: UUID) -> NSItemProvider {
        isDragging = true
        return dragProvider(
            BrowserDragPayload(
                kind: .folder, spaceID: activeSpace.id,
                ids: selectedFolders.contains(folder) ? selectedLooseTabIDs : [],
                folderIDs: selectedFolders.contains(folder) ? selectionRootFolders : [folder]), url: nil)
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
                    let target = before.flatMap { id in self.activeSpace.tabs.first { $0.id == id } }
                    let id = self.open(
                        url,
                        placement: placement ?? target?.placement ?? dropFolder.flatMap { id in
                            self.activeSpace.folders.first { $0.id == id }?.placement ?? .saved
                        } ?? .current, folderID: dropFolder)
                    self.reorderSidebarItems([id], in: destination, before: before)
                    self.changed()
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
        if payload.kind == .space {
            guard payload.spaceID != spaceID,
                let index = session.spaces.firstIndex(where: { $0.id == payload.spaceID })
            else { return }
            let moving = session.spaces.remove(at: index)
            let destination = session.spaces.firstIndex { $0.id == spaceID } ?? session.spaces.count
            session.spaces.insert(moving, at: destination)
            changed()
            return
        }
        let destinationSpace = session.spaces[spaceIndex(spaceID)]
        let beforeFolder = before.flatMap { id in destinationSpace.folders.first { $0.id == id } }
        let beforeTab = before.flatMap { id in destinationSpace.tabs.first { $0.id == id } }
        let destinationParent = folder ?? beforeFolder?.parentID ?? beforeTab?.folderID
        let location =
            placement ?? beforeFolder?.placement ?? beforeTab?.placement
            ?? destinationParent.flatMap { id in destinationSpace.folders.first { $0.id == id }?.placement }
        if !payload.folderIDs.isEmpty {
            let nested = payload.folderIDs.reduce(into: Set<UUID>()) { $0.formUnion(descendants($1, in: source)) }
            guard location != .pinned,
                destinationParent.map({ !nested.contains($0) }) ?? true,
                before.map({ !nested.contains($0) }) ?? true
            else { return }
            for id in payload.folderIDs {
                if payload.spaceID == spaceID {
                    moveFolderLocally(id, into: destinationParent, placement: location, before: before)
                } else {
                    moveFolder(
                        id, from: payload.spaceID, to: spaceID, parentID: destinationParent, placement: location,
                        before: before)
                }
            }
            if payload.kind == .folder && payload.ids.isEmpty { return }
        }
        let ids = relatedTabIDs(payload.ids).filter { id in source.tabs.contains(where: { $0.id == id }) }
        guard !ids.isEmpty else { return }
        if payload.spaceID != spaceID {
            moveTabs(ids, to: spaceID, folderID: destinationParent, placement: location, before: before)
            return
        }
        let s = spaceIndex(spaceID)
        let target = before.flatMap { id in session.spaces[s].tabs.first { $0.id == id } }
        if let before, ids.contains(before) { return }
        var moved = session.spaces[s].tabs.filter { ids.contains($0.id) }
        session.spaces[s].tabs.removeAll { ids.contains($0.id) }
        for i in moved.indices {
            moved[i].placement =
                location ?? target?.placement ?? folder.map { id in
                    session.spaces[s].folders.first { $0.id == id }?.placement ?? .saved
                } ?? moved[i].placement
            moved[i].folderID = moved[i].placement == .pinned ? nil : destinationParent
            if moved[i].placement == .current {
                moved[i].savedURL = nil
            } else if moved[i].savedURL == nil {
                moved[i].savedURL = moved[i].url
            }
        }
        let index =
            before.flatMap { id in session.spaces[s].tabs.firstIndex { $0.id == id } } ?? session.spaces[s].tabs.count
        session.spaces[s].tabs.insert(contentsOf: moved, at: index)
        reorderSidebarItems(ids, in: spaceID, before: before)
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
    func moveTabs(
        _ ids: [UUID], to destination: UUID, folderID: UUID? = nil, placement: BrowserTab.Placement? = nil,
        before: UUID? = nil
    ) {
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
                if tab.placement == .current {
                    tab.savedURL = nil
                } else if tab.savedURL == nil {
                    tab.savedURL = tab.url
                }
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
            reorderSidebarItems(ids, in: destination, before: before)
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
    func moveFolderLocally(
        _ id: UUID, into parentID: UUID?, placement: BrowserTab.Placement? = nil, before: UUID? = nil
    ) {
        let s = spaceIndex(activeSpace.id)
        guard let folder = activeSpace.folders.first(where: { $0.id == id }) else { return }
        let nested = descendants(id, in: activeSpace)
        guard parentID.map({ !nested.contains($0) }) ?? true,
            parentID.map({ parent in activeSpace.folders.contains { $0.id == parent && $0.kind == .regular } }) ?? true
        else { return }
        let parent = parentID.flatMap { parent in activeSpace.folders.first { $0.id == parent } }
        let location = placement ?? parent?.placement ?? folder.placement ?? .saved
        guard location != .pinned, folder.kind != .github || location == .saved else { return }
        var candidate = session
        for i in candidate.spaces[s].folders.indices where nested.contains(candidate.spaces[s].folders[i].id) {
            candidate.spaces[s].folders[i].placement = location
            if candidate.spaces[s].folders[i].id == id { candidate.spaces[s].folders[i].parentID = parentID }
        }
        for i in candidate.spaces[s].tabs.indices
        where candidate.spaces[s].tabs[i].folderID.map(nested.contains) == true {
            candidate.spaces[s].tabs[i].placement = location
            if location == .current {
                candidate.spaces[s].tabs[i].savedURL = nil
            } else if candidate.spaces[s].tabs[i].savedURL == nil {
                candidate.spaces[s].tabs[i].savedURL = candidate.spaces[s].tabs[i].url
            }
        }
        if let before, before != id,
            let index = candidate.spaces[s].folders.firstIndex(where: { $0.id == id })
        {
            let moved = candidate.spaces[s].folders.remove(at: index)
            let target = candidate.spaces[s].folders.firstIndex { $0.id == before } ?? candidate.spaces[s].folders.count
            candidate.spaces[s].folders.insert(moved, at: target)
        }
        guard (try? candidate.validate()) != nil else { return }
        session = candidate
        reorderSidebarItems([id], in: activeSpace.id, before: before)
        changed()
    }

    func moveFolder(
        _ id: UUID, from source: UUID, to destination: UUID, parentID: UUID? = nil,
        placement: BrowserTab.Placement? = nil, before: UUID? = nil
    ) {
        guard source != destination, let space = session.spaces.first(where: { $0.id == source }),
            let target = session.spaces.first(where: { $0.id == destination }),
            parentID.map({ parent in target.folders.contains { $0.id == parent && $0.kind == .regular } }) ?? true
        else { return }
        let targetPlacement =
            placement ?? parentID.flatMap { parent in target.folders.first { $0.id == parent }?.placement }
        guard targetPlacement != .pinned else { return }
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
                session.spaces[targetIndex].isPrivate
                    || session.spaces[targetIndex].folders.contains(where: { $0.kind == .github })
            {
                return
            }
            var folders = session.spaces[sourceIndex].folders.filter { folderIDs.contains($0.id) }
            for i in folders.indices {
                if folders[i].id == id { folders[i].parentID = parentID }
                if let targetPlacement { folders[i].placement = targetPlacement }
            }
            guard !folders.contains(where: { $0.kind == .github && $0.placement == .current }) else { return }
            var moving = session.spaces[sourceIndex].tabs.filter { tabs.contains($0.id) }
            for i in moving.indices {
                if let targetPlacement {
                    moving[i].placement = targetPlacement
                    moving[i].savedURL = targetPlacement == .current ? nil : moving[i].savedURL ?? moving[i].url
                }
            }
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
            reorderSidebarItems([id], in: destination, before: before)
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
