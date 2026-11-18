import Observation
import SwiftUI

/// Crest keeps the last shown resident tab on a collapsed folder's path.
/// This is window presentation state; it never enters the session checkpoint.
@MainActor
final class BrowserSidebarFolderVisibility {
    @Observable final class Entry {
        var keptTabID: UUID?
        @ObservationIgnored var wasExpanded: Bool?
    }
    private var entries: [UUID: Entry] = [:]

    func state(for id: UUID) -> Entry {
        if let entry = entries[id] { return entry }
        let entry = Entry()
        entries[id] = entry
        return entry
    }

    func expansionWillChange(_ folder: UUID, expanded: Bool, selected: UUID?, in space: BrowserSpace) {
        let entry = state(for: folder)
        entry.wasExpanded = expanded
        entry.keptTabID = expanded ? nil : selected.flatMap { space.folderPath(to: $0).contains(folder) ? $0 : nil }
    }

    func reconcile(space: BrowserSpace, selected: UUID?, resident: Set<UUID>) {
        let selectedPath = selected.map { space.folderPath(to: $0) } ?? []
        for folder in space.folders {
            let entry = state(for: folder.id)
            if entry.wasExpanded != folder.isExpanded {
                entry.keptTabID =
                    folder.isExpanded ? nil : selected.flatMap { selectedPath.contains(folder.id) ? $0 : nil }
            }
            entry.wasExpanded = folder.isExpanded
            if let kept = entry.keptTabID,
                !resident.contains(kept) || !space.folderPath(to: kept).contains(folder.id)
            {
                entry.keptTabID = nil
            }
            if !folder.isExpanded, let selected, resident.contains(selected), selectedPath.contains(folder.id) {
                entry.keptTabID = selected
            }
        }
    }

    func prune(keeping valid: Set<UUID>) {
        for (id, entry) in entries where !valid.contains(id) {
            entry.keptTabID = nil
            entries[id] = nil
        }
    }
}

struct BrowserSidebarFolderReconciler: View {
    let store: BrowserStore
    private struct Snapshot: Equatable {
        let spaceID: UUID
        let folders: [BrowserFolder]
        let tabs: [BrowserTab]
        let selected: UUID?
        let resident: Set<UUID>
    }
    private var snapshot: Snapshot {
        Snapshot(
            spaceID: store.activeSpace.id, folders: store.activeSpace.folders, tabs: store.activeSpace.tabs,
            selected: store.selectedTab?.id, resident: Set(store.pages.keys))
    }
    var body: some View {
        Color.clear.allowsHitTesting(false).accessibilityHidden(true)
            .onChange(of: snapshot, initial: true) { _, _ in reconcile() }
            .onChange(of: store.owner.sidebarDrag.payload != nil) { _, dragging in if !dragging { reconcile() } }
    }
    private func reconcile() {
        guard store.owner.sidebarDrag.payload == nil else { return }
        store.sidebarFolders.prune(keeping: Set(store.session.spaces.flatMap { $0.folders.map(\.id) }))
        store.sidebarFolders.reconcile(
            space: store.activeSpace, selected: store.selectedTab?.id,
            resident: Set(store.pages.keys))
    }
}
