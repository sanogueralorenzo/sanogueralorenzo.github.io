import Foundation

struct ImportQueue: Equatable, Sendable {
    var sources: [ImportSource]
    var index: Int
    var current: ImportSource? { sources.indices.contains(index) ? sources[index] : nil }
    var hasMoreAfterCurrent: Bool { index + 1 < sources.count }
}

enum ImportStep: String, CaseIterable, Sendable {
    case importBrowser, review, complete
    typealias Kinds = ImportStep
    var kind: Kinds { self }
    var name: String { rawValue }
    static let all = allCases
}
enum ImportPhase: String, Sendable {
    case idle, reading, reviewing, committing
    var isBusy: Bool { self == .reading || self == .committing }
}
enum ImportFailureReason: String, Sendable {
    case sourceUnavailable, dataFolder, read, `import`
    var returnsToReview: Bool { self == .import }
}

struct ImportReviewSpace: Equatable, Sendable {
    let source: SpaceState
    var included: Bool
    var destinationID: UUID?
    var customization: SpaceCustomization
    var includedTabIDs: [UUID]
    var duplicateTabIDs: [UUID] = []
    var matchedTabIDs: [UUID] = []
    var placements: [TabPlacementChoice] = []
    var extensions: [ImportExtension]
    var includedExtensionIDs: [String]

    var shownName: String {
        let name = customization.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? SpaceCustomization.untitledName : name
    }
    var broughtExtensions: [ImportExtension] {
        included ? extensions.filter { includedExtensionIDs.contains($0.extensionID) } : []
    }
    var makesNewSpace: Bool { included && destinationID == nil }
    func ordered(_ ids: Set<UUID>) -> [UUID] { source.tabs.map(\.id).filter(ids.contains) }
}

struct ImportReview: Equatable, Sendable {
    let source: ImportSource
    var spaces: [ImportReviewSpace]
    var overflowTabIDs: [UUID] = []
    var shownSpaceID: UUID?
    var leftOut: [ImportLeftOut]
    var spaceRoom: Int
    var browserTitle: String?

    var title: String { browserTitle ?? source.title }
    var hasIncludedSpaces: Bool { spaces.contains(where: \.included) }
    var includedTabCount: Int { spaces.filter(\.included).reduce(0) { $0 + $1.includedTabIDs.count } }
    var includedExtensionCount: Int { spaces.reduce(0) { $0 + $1.broughtExtensions.count } }
    var nextSpaceID: UUID? {
        guard let index = spaces.firstIndex(where: { $0.source.id == shownSpaceID }) else {
            return spaces.first?.source.id
        }
        return spaces.indices.contains(index + 1) ? spaces[index + 1].source.id : nil
    }
    var showsLastSpace: Bool { !spaces.isEmpty && shownSpaceID == spaces.last?.source.id }
    var newSpaceCapacity: Int { max(0, spaceRoom - spaces.filter(\.makesNewSpace).count) }
    var extensionInstalls: [ImportExtensionInstall] {
        var installs: [ImportExtensionInstall] = []
        for space in spaces {
            for item in space.broughtExtensions {
                let destination = space.destinationID ?? space.source.id
                if let index = installs.firstIndex(where: { $0.extensionID == item.extensionID }) {
                    if installs[index].iconPath == nil { installs[index].iconPath = item.iconPath }
                    if !installs[index].spaceIDs.contains(destination) { installs[index].spaceIDs.append(destination) }
                } else {
                    installs.append(
                        ImportExtensionInstall(
                            extensionID: item.extensionID, name: item.name, iconPath: item.iconPath,
                            spaceIDs: [destination]))
                }
            }
        }
        return installs
    }

    static func started(_ action: ReviewImport, over context: ImportReviewContext) -> Self {
        var joined: Set<UUID> = []
        var created = 0
        let offers = Dictionary(grouping: action.extensions ?? [], by: \.spaceID).mapValues { group in
            var seen: Set<String> = []
            return group.flatMap(\.extensions).filter { seen.insert($0.extensionID).inserted }
        }
        let reviews = action.spaces.map { space in
            let key = matchKey(space.settings.name)
            let match =
                key.isEmpty
                ? nil : context.destinations.first { !joined.contains($0.id) && matchKey($0.settings.name) == key }
            if let match { joined.insert(match.id) }
            let included = match != nil || created < context.room
            if included && match == nil { created += 1 }
            let duplicates = Set(match.map { matchingTabs(space, in: $0) } ?? [])
            let offered = offers[space.id] ?? []
            return ImportReviewSpace(
                source: space, included: included, destinationID: match?.id,
                customization: SpaceCustomization(name: match?.settings.name ?? space.settings.name),
                includedTabIDs: included ? space.tabs.map(\.id).filter { !duplicates.contains($0) } : [],
                extensions: offered, includedExtensionIDs: offered.map(\.extensionID))
        }
        return ImportReview(
            source: action.source, spaces: reviews, shownSpaceID: action.spaces.first?.id,
            leftOut: action.leftOut ?? [], spaceRoom: context.room, browserTitle: action.title
        ).analyzed(over: context)
    }

    mutating func edit(_ id: UUID, over context: ImportReviewContext, _ edit: (inout ImportReviewSpace) -> Void) {
        guard let index = spaces.firstIndex(where: { $0.source.id == id }) else { return }
        var edited = spaces[index]
        edit(&edited)
        guard
            !edited.makesNewSpace || spaces[index].makesNewSpace || spaces.filter(\.makesNewSpace).count < context.room
        else { return }
        spaces[index] = edited
        self = analyzed(over: context)
    }

    func analyzed(over context: ImportReviewContext) -> Self {
        let destinations = Dictionary(uniqueKeysWithValues: context.destinations.map { ($0.id, $0) })
        var pinned = destinations.mapValues { $0.tabs.filter { $0.placement == .pinned }.count }
        var created: [UUID: Int] = [:]
        var next = self
        next.overflowTabIDs = []
        next.spaceRoom = context.room
        for index in next.spaces.indices {
            var space = next.spaces[index]
            let destination = space.destinationID.flatMap { destinations[$0] }
            space.duplicateTabIDs = destination.map { Self.matchingTabs(space.source, in: $0) } ?? []
            space.matchedTabIDs =
                space.included ? destination.map { Self.matchingTabs($0, in: space.source) } ?? [] : []
            next.spaces[index] = space
            guard space.included else { continue }
            let key = space.destinationID ?? space.source.id
            var count = space.destinationID == nil ? created[key] ?? 0 : pinned[key] ?? 0
            let included = Set(space.includedTabIDs)
            let placements = Dictionary(
                space.placements.map { ($0.tabID, $0.placement) }, uniquingKeysWith: { _, last in last })
            for tab in space.source.tabs
            where included.contains(tab.id) && (placements[tab.id] ?? tab.placement) == .pinned {
                if count >= TabPlacement.pinnedCapacity { next.overflowTabIDs.append(tab.id) } else { count += 1 }
            }
            if space.destinationID == nil { created[key] = count } else { pinned[key] = count }
        }
        return next
    }

    private static func matchingTabs(_ source: SpaceState, in other: SpaceState) -> [UUID] {
        func key(_ url: String) -> Data { Data((BrowserWebAddress.normalized(url) ?? url).utf8) }
        let keys = Set(other.tabs.compactMap(\.url).map(key))
        return source.tabs.filter { $0.url.map { keys.contains(key($0)) } == true }.map(\.id)
    }
    private static func matchKey(_ text: String) -> String {
        let scalars = text.decomposedStringWithCompatibilityMapping.unicodeScalars.filter {
            switch $0.properties.generalCategory {
            case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter, .decimalNumber,
                .letterNumber, .otherNumber:
                true
            default: false
            }
        }
        return String(String.UnicodeScalarView(scalars)).lowercased()
    }
}

struct ImportReviewContext {
    let destinations: [SpaceState]
    let room: Int
    @MainActor init(_ workspace: WorkspaceModel) {
        let deleting = Set(workspace.spaceDeletions.map(\.spaceID))
        destinations =
            workspace.isDisposableSeed ? [] : workspace.spaces.models.filter { !deleting.contains($0.id) }.map(\.value)
        room = max(0, CapacityLimits.current.spaces - (workspace.isDisposableSeed ? 0 : workspace.spaces.models.count))
    }
}
