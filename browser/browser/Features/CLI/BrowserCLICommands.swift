import Foundation

@MainActor
enum BrowserCLICommands {
    static func execute(
        _ arguments: [String], owner: BrowserSessionOwner, store: BrowserStore?
    ) -> BrowserCLIResponse {
        do { return try perform(arguments, owner: owner, store: store) }
        catch { return BrowserCLIResponse(error: error.localizedDescription) }
    }

    private static func perform(
        _ arguments: [String], owner: BrowserSessionOwner, store: BrowserStore?
    ) throws -> BrowserCLIResponse {
        let values = arguments.dropFirst(2)
        let spaces = owner.session.spaces.filter { !$0.isPrivate }
        let selectedSpaceID = store?.activeSpace.id ?? owner.session.selectedSpaceID

        func space(_ selector: String?) throws -> BrowserSpace {
            guard let selector else {
                guard let active = spaces.first(where: { $0.id == selectedSpaceID }) else {
                    throw BrowserCLIError("Specify a regular Space with --space.")
                }
                return active
            }
            if let id = UUID(uuidString: selector), let match = spaces.first(where: { $0.id == id }) { return match }
            let matches = spaces.filter { $0.name == selector }
            guard let match = matches.first else { throw BrowserCLIError("Regular Space not found: \(selector)") }
            guard matches.count == 1 else { throw BrowserCLIError("More than one Space has that name. Use its ID.") }
            return match
        }

        func window() throws -> BrowserStore {
            guard let store else { throw BrowserCLIError("Open a Browser window and try again.") }
            return store
        }

        func checkpoint() throws {
            guard owner.flush() else {
                throw BrowserCLIError(owner.storageError ?? "Browser could not save the session.")
            }
        }

        func spaceSummary(_ space: BrowserSpace) -> BrowserCLIResponse.Space {
            .init(id: space.id, name: space.name, selected: space.id == selectedSpaceID)
        }

        func tabSummary(_ tab: BrowserTab, in space: BrowserSpace) -> BrowserCLIResponse.Tab {
            .init(
                id: tab.id, spaceID: space.id, title: tab.customTitle ?? tab.title, url: tab.url,
                placement: tab.placement,
                selected: tab.id == (store.map { $0.sidebarSelectedTabID(in: space) } ?? space.selectedTabID))
        }

        switch Array(arguments.prefix(2)) {
        case ["spaces", "list"] where values.isEmpty:
            return .init(spaces: spaces.map(spaceSummary))
        case ["spaces", "create"] where !values.isEmpty:
            guard values.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw BrowserCLIError("Every Space needs a name.")
            }
            let names = values.map(BrowserSpace.normalizedName)
            guard names.count <= BrowserSession.maximumSpaceCount - owner.session.spaces.count else {
                throw BrowserCLIError("Browser supports up to \(BrowserSession.maximumSpaceCount) Spaces.")
            }
            guard Set(names).count == names.count, Set(names).isDisjoint(with: spaces.map(\.name)) else {
                throw BrowserCLIError("Space names must be unique within the batch and among regular Spaces.")
            }
            let ids = try Set(names.map { try owner.addSpace(name: $0) })
            try checkpoint()
            return .init(spaces: owner.session.spaces.filter { ids.contains($0.id) }.map(spaceSummary))
        case ["spaces", "select"] where values.count == 1:
            let target = try space(values.first)
            try window().selectSpace(target.id)
            try checkpoint()
            return .init(spaces: [.init(id: target.id, name: target.name, selected: true)])
        case ["spaces", "rename"] where values.count == 2:
            let target = try space(values.first)
            let input = values.last!
            guard !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw BrowserCLIError("The Space needs a name.")
            }
            let name = BrowserSpace.normalizedName(input)
            guard !spaces.contains(where: { $0.id != target.id && $0.name == name }) else {
                throw BrowserCLIError("A regular Space already has that name.")
            }
            try window().saveSpace(id: target.id, name: name)
            try checkpoint()
            return .init(spaces: [.init(id: target.id, name: name, selected: target.id == selectedSpaceID)])
        case ["tabs", "list"]:
            let target = try space(spaceOption(values))
            return .init(tabs: target.tabs.map { tabSummary($0, in: target) })
        case ["tabs", "open"] where !values.isEmpty:
            let target = try space(spaceOption(values.dropFirst()))
            guard let url = SearchProvider.explicitAddress(values.first!) else {
                throw BrowserCLIError("Provide a website or file URL.")
            }
            let store = try window()
            guard store.canChangeTabCount(by: 1, in: target.id) else {
                throw BrowserCLIError("That Space has reached its tab limit.")
            }
            store.selectSpace(target.id)
            guard let id = store.open(url), let tab = store.activeSpace.tabs.first(where: { $0.id == id }) else {
                throw BrowserCLIError("Browser could not open that URL.")
            }
            try checkpoint()
            return .init(tabs: [tabSummary(tab, in: store.activeSpace)])
        case ["tabs", "select"], ["tabs", "close"]:
            guard values.count == 1, let id = UUID(uuidString: values.first!) else {
                throw BrowserCLIError("Provide a tab ID from browser tabs list.")
            }
            guard spaces.contains(where: { $0.tabs.contains { $0.id == id } }) else {
                throw BrowserCLIError("Tab not found in a regular Space.")
            }
            let store = try window()
            if arguments[1] == "close" {
                store.requestCloseTab(id)
                return .init(message: "Close requested. Browser may ask for confirmation.")
            }
            store.selectTab(id)
            try checkpoint()
            return .init(message: "Tab selected.")
        default:
            throw BrowserCLIError(BrowserCLI.usage)
        }
    }

    private static func spaceOption(_ values: ArraySlice<String>) throws -> String? {
        if values.isEmpty { return nil }
        guard values.count == 2, values.first == "--space" else { throw BrowserCLIError(BrowserCLI.usage) }
        return values.last
    }
}
