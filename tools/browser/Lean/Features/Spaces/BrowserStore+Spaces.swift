import Foundation
import WebKit

extension BrowserStore {
    func saveSpace(id: UUID?, name: String, color: Int, isPrivate: Bool = false) {
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id, let index = session.spaces.firstIndex(where: { $0.id == id }) {
            session.spaces[index].name = title.isEmpty ? "Space" : String(title.prefix(256))
            session.spaces[index].color = color
        } else {
            var space = BrowserSpace()
            space.name = title.isEmpty ? "Space" : String(title.prefix(256))
            space.color = color
            space.isPrivate = isPrivate
            session.spaces.append(space)
            selectSpace(space.id)
            _ = integration(for: space.id)
        }
        changed()
    }

    func deleteSpace(_ id: UUID, prepared: Bool = false) {
        guard let space = session.spaces.first(where: { $0.id == id }),
            space.isPrivate || session.spaces.filter({ !$0.isPrivate }).count > 1
        else { return }
        Task {
            if !prepared {
                guard await prepareTabs(space.tabs.map(\.id)), await prepareToDeleteSpace(id) else { return }
            }
            guard let current = session.spaces.first(where: { $0.id == id }),
                Set(current.tabs.map(\.id)) == Set(space.tabs.map(\.id))
            else { return }
            for tab in space.tabs { unload(tab.id) }
            integrations.removeValue(forKey: id)?.invalidate()
            profiles[id] = nil
            var blocker = owner.contentBlockers.removeValue(forKey: id)
            session.spaces.removeAll { $0.id == id }
            session.history.removeAll { $0.spaceID == id }
            session.archive.removeAll { $0.spaceID == id }
            if !session.spaces.contains(where: { !$0.isPrivate }) { session.spaces.append(BrowserSpace()) }
            let fallback = session.spaces.first(where: { !$0.isPrivate })!.id
            for context in owner.contexts.values where context.windowState.spaceID == id {
                context.windowState.spaceID = fallback
                context.resumePages()
            }
            for i in session.windows.indices {
                session.windows[i].tabsBySpace[id] = nil
                session.windows[i].emptySpaces.remove(id)
                if session.windows[i].spaceID == id { session.windows[i].spaceID = fallback }
            }
            if session.selectedSpaceID == id { session.selectedSpaceID = fallback }
            changed()
            await blocker?.removeData()
            blocker = nil
            if !space.isPrivate { WKWebsiteDataStore.remove(forIdentifier: id) { _ in } }
        }
    }

    func profile(for spaceID: UUID) -> WKWebsiteDataStore {
        if let profile = profiles[spaceID] { return profile }
        let profile =
            session.spaces.first(where: { $0.id == spaceID })?.isPrivate == true
            ? WKWebsiteDataStore.nonPersistent() : WKWebsiteDataStore(forIdentifier: spaceID)
        profiles[spaceID] = profile
        return profile
    }

    func savePrivateSpace(name: String = "Private", color: Int = 4) {
        var space = BrowserSpace()
        space.name = name
        space.color = color
        space.isPrivate = true
        session.spaces.append(space)
        selectSpace(space.id)
        _ = integration(for: space.id)
        changed()
    }

    func adjacentSpace(_ delta: Int) {
        guard let index = session.spaces.firstIndex(where: { $0.id == activeSpace.id }) else { return }
        selectSpace(session.spaces[(index + delta + session.spaces.count) % session.spaces.count].id)
    }
}
