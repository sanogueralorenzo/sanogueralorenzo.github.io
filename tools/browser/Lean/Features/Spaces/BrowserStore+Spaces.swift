import Foundation
import WebKit

extension BrowserStore {
    @discardableResult
    func moveSpace(_ id: UUID, by delta: Int) -> Bool {
        guard let index = session.spaces.firstIndex(where: { $0.id == id }),
            session.spaces.indices.contains(index + delta)
        else { return false }
        return moveSpace(id, relativeTo: session.spaces[index + delta].id, after: delta > 0)
    }

    @discardableResult
    func moveSpace(_ id: UUID, relativeTo destination: UUID, after: Bool = false) -> Bool {
        guard !isClosed, id != destination,
            let index = session.spaces.firstIndex(where: { $0.id == id }),
            session.spaces.contains(where: { $0.id == destination })
        else { return false }
        let moving = session.spaces.remove(at: index)
        let target = session.spaces.firstIndex { $0.id == destination }!
        session.spaces.insert(moving, at: target + (after ? 1 : 0))
        changed()
        return true
    }

    func saveSpace(id: UUID?, name: String, color: Int, isPrivate: Bool = false) {
        guard !isClosed else { return }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id {
            guard let index = session.spaces.firstIndex(where: { $0.id == id }) else { return }
            session.spaces[index].name = title.isEmpty ? "Space" : String(title.prefix(256))
            session.spaces[index].color = color
            changed()
        } else {
            do {
                let id = try owner.addSpace(name: title, color: color, isPrivate: isPrivate)
                selectSpace(id)
                _ = integration(for: id)
            } catch {
                showNotice(error.localizedDescription)
            }
        }
    }

    func deleteSpace(_ id: UUID, prepared: Bool = false) {
        guard !isClosed || prepared, let space = session.spaces.first(where: { $0.id == id }),
            space.isPrivate || session.spaces.filter({ !$0.isPrivate }).count > 1
        else { return }
        let check = BrowserPageCloseCheck(space.tabs.map(\.id), owner: owner)
        Task {
            if !prepared {
                guard await prepareTabs(space.tabs.map(\.id)), await prepareToDeleteSpace(id) else { return }
            }
            guard !isClosed || prepared, let current = session.spaces.first(where: { $0.id == id }),
                check.isCurrent(in: owner),
                current.isPrivate || session.spaces.filter({ !$0.isPrivate }).count > 1,
                Set(current.tabs.map(\.id)) == Set(space.tabs.map(\.id)),
                Set(current.folders.map(\.id)) == Set(space.folders.map(\.id)),
                owner.activeDownloadRequests(in: id).isEmpty,
                !prepared || !owner.contexts.values.contains(where: { !$0.isClosed && $0.activeSpace.id == id })
            else { return }
            for tab in space.tabs { unload(tab.id) }
            integrations.removeValue(forKey: id)?.invalidate()
            profiles[id] = nil
            var blocker = owner.contentBlockers.removeValue(forKey: id)
            session.spaces.removeAll { $0.id == id }
            session.history.removeAll { $0.spaceID == id }
            session.archive.removeAll { $0.spaceID == id }
            session.downloads.removeAll { $0.spaceID == id }
            let fallback = session.spaces.first(where: { !$0.isPrivate })!.id
            for context in owner.contexts.values {
                context.sidebarScrollOffsets[id] = nil
                if context.windowState.spaceID == id {
                    context.sidebarSpaceStep = nil
                    context.windowState.spaceID = fallback
                    if !context.isClosed { context.resumePages() }
                }
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
        guard !isClosed else { return }
        do {
            let id = try owner.addSpace(name: name, color: color, isPrivate: true)
            selectSpace(id)
            _ = integration(for: id)
        } catch {
            showNotice(error.localizedDescription)
        }
    }

    func adjacentSpace(_ delta: Int) {
        guard let index = session.spaces.firstIndex(where: { $0.id == activeSpace.id }) else { return }
        selectSpace(session.spaces[(index + delta + session.spaces.count) % session.spaces.count].id, step: delta)
    }
}

extension BrowserSessionOwner {
    func addSpace(name: String, color: Int, isPrivate: Bool = false) throws -> UUID {
        guard session.spaces.count < BrowserSession.maximumSpaceCount else { throw BrowserSpaceFailure.limit }
        let title = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var space = BrowserSpace()
        space.name = title.isEmpty ? "Space" : String(title.prefix(256))
        space.color = color
        space.isPrivate = isPrivate
        session.spaces.append(space)
        changed()
        return space.id
    }
}

private enum BrowserSpaceFailure: LocalizedError {
    case limit
    var errorDescription: String? {
        "You can have up to \(BrowserSession.maximumSpaceCount) Spaces. Delete a Space before adding another."
    }
}
