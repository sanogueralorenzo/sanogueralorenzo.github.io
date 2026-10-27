import Foundation

struct BrowserTab: Codable, Identifiable, Equatable {
    enum Placement: String, Codable { case pinned, saved, current }
    var id = UUID()
    var title = "New Tab"
    var url: URL?
    var savedURL: URL?
    var placement = Placement.current
    var folderID: UUID?
    var customTitle: String?
    var favicon: Data?
    var isSettings = false
    var interactionState: Data?
    var documentState: BrowserDocumentState?
    var lastUsed = Date()
    var zoom = 1.0
}

struct BrowserDocumentState: Codable, Equatable, Sendable {
    struct Field: Codable, Equatable, Sendable {
        var selector: String
        var value: String
        var checked: Bool?
    }
    var url: String
    var x: Double
    var y: Double
    var fields: [Field]
}

struct BrowserFolder: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case regular, github }
    var id = UUID()
    var title = "New Folder"
    var parentID: UUID?
    var isExpanded = true
    var kind = Kind.regular
    var placement: BrowserTab.Placement?
    var githubOptions = GitHubLiveFolderOptions.default
}

struct BrowserSpace: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "Personal"
    var color = 0
    var isPrivate = false
    var tabs: [BrowserTab] = []
    var folders: [BrowserFolder] = []
    var sidebarOrderIDs: [UUID]?
    var selectedTabID: UUID?
    var splits: [BrowserSplit] = []
    var githubDismissed = false
    var permissions: [BrowserSitePermission] = []
    var downloadDirectory: Data?
    var browsingPreferences: BrowserSpacePreferences?
}

struct BrowserSitePermission: Codable, Identifiable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case camera, microphone, location, notifications, screenCapture, popups, automaticDownloads
        var id: String { rawValue }
        var label: String {
            switch self {
            case .camera: "Camera"
            case .microphone: "Microphone"
            case .location: "Location"
            case .notifications: "Notifications"
            case .screenCapture: "Screen Sharing"
            case .popups: "Pop-up Windows"
            case .automaticDownloads: "Automatic Downloads"
            }
        }
    }
    enum Decision: String, Codable, CaseIterable { case ask, allow, deny }
    var origin: String
    var kind: Kind
    var decision: Decision
    var id: String { origin + ":" + kind.rawValue }
}

struct BrowserVisit: Codable, Identifiable {
    var id = UUID()
    var spaceID: UUID
    var title: String
    var url: URL
    var date = Date()
    var count = 1
}

struct BrowserArchiveEntry: Codable, Identifiable {
    var id = UUID()
    var spaceID: UUID
    var tab: BrowserTab
    var wasDeletedFromLiveFolder: Bool?
    var date = Date()
}

struct BrowserDownloadRecord: Codable, Identifiable {
    enum Status: String, Codable { case choosing, running, paused, failed, completed, cancelled }
    var id = UUID()
    var spaceID: UUID
    var name: String
    var source: URL?
    var requestMethod = "GET"
    var destination: URL?
    var destinationBookmark: Data?
    var mimeType: String?
    var status = Status.choosing
    var received: Int64 = 0
    var expected: Int64 = 0
    var resumeData: Data?
    var error: String?
    var risk: [String] = []
    var date = Date()
}

struct BrowserPreferences: Codable {
    var searchProvider = SearchProvider.google
    var searchSuggestions = false
    var blocksContent = true
    var translatesAutomatically = false
    var translationLanguage = "en"
    var excludedLanguages: Set<String> = []
    var downloadsAskEveryTime = true
    var sidebarWidth: Double?
    var defaultPageZoom: Double?
}

struct BrowserWindowState: Codable, Identifiable {
    var id = UUID()
    var spaceID: UUID
    var tabsBySpace: [UUID: UUID] = [:]
    var recentTabs: [UUID] = []
    var emptySpaces: Set<UUID> = []
    var frame: String?
    var isOpen = true
}

struct BrowserSession: Codable {
    var format = 1
    var revision: UInt64 = 0
    var spaces = [BrowserSpace()]
    var selectedSpaceID: UUID?
    var windows: [BrowserWindowState] = []
    var history: [BrowserVisit] = []
    var archive: [BrowserArchiveEntry] = []
    var downloads: [BrowserDownloadRecord] = []
    var preferences = BrowserPreferences()

    func persistent() -> BrowserSession {
        var copy = self
        let ids = Set(spaces.filter { !$0.isPrivate }.map(\.id))
        copy.spaces.removeAll { !ids.contains($0.id) }
        copy.history.removeAll { !ids.contains($0.spaceID) }
        copy.archive.removeAll { !ids.contains($0.spaceID) }
        copy.downloads.removeAll { !ids.contains($0.spaceID) }
        copy.windows.removeAll { !ids.contains($0.spaceID) }
        let tabs = Set(copy.spaces.flatMap { $0.tabs.map(\.id) })
        for i in copy.windows.indices {
            copy.windows[i].tabsBySpace = copy.windows[i].tabsBySpace.filter {
                ids.contains($0.key) && tabs.contains($0.value)
            }
            copy.windows[i].recentTabs.removeAll { !tabs.contains($0) }
            copy.windows[i].emptySpaces = copy.windows[i].emptySpaces.intersection(ids)
        }
        copy.selectedSpaceID = ids.contains(selectedSpaceID ?? UUID()) ? selectedSpaceID : copy.spaces.first?.id
        return copy
    }

    func validate() throws {
        guard format == 1, !spaces.isEmpty, spaces.count <= 64 else { throw CocoaError(.fileReadCorruptFile) }
        var identifiers = Set<UUID>()
        for space in spaces {
            guard identifiers.insert(space.id).inserted, space.tabs.count <= 20_000, space.folders.count <= 4096,
                space.name.utf8.count <= 4096
            else {
                throw CocoaError(.fileReadCorruptFile)
            }
            guard Set(space.folders.map(\.id)).count == space.folders.count else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let folders = Dictionary(uniqueKeysWithValues: space.folders.map { ($0.id, $0) })
            for folder in space.folders {
                guard identifiers.insert(folder.id).inserted else { throw CocoaError(.fileReadCorruptFile) }
                var chain = Set([folder.id])
                var parent = folder.parentID
                while let id = parent {
                    guard chain.count < 33, chain.insert(id).inserted, let ancestor = folders[id] else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    parent = ancestor.parentID
                }
            }
            let tabs = Set(space.tabs.map(\.id))
            for tab in space.tabs {
                guard identifiers.insert(tab.id).inserted, tab.title.utf8.count <= 16_384,
                    (tab.interactionState?.count ?? 0) <= 8 * 1_024 * 1_024,
                    tab.zoom.isFinite && (0.25...5).contains(tab.zoom),
                    tab.folderID.map({ folders[$0] != nil }) ?? true,
                    tab.url.map({
                        ["http", "https", "file", "about", "data", "blob"].contains($0.scheme?.lowercased() ?? "")
                    }) ?? true
                else {
                    throw CocoaError(.fileReadCorruptFile)
                }
            }
            var splitTabs = Set<UUID>()
            for split in space.splits {
                guard identifiers.insert(split.id).inserted, (2...4).contains(split.tabIDs.count),
                    split.tabIDs.allSatisfy({ tabs.contains($0) && splitTabs.insert($0).inserted }),
                    split.fractions.count == split.tabIDs.count,
                    split.fractions.allSatisfy({ $0.isFinite && $0 > 0 }),
                    abs(split.fractions.reduce(0, +) - 1) < 0.01
                else { throw CocoaError(.fileReadCorruptFile) }
            }
        }
    }
}

enum BrowserUtility: String, Identifiable {
    case history = "History"
    case archive = "Archive"
    case downloads = "Downloads"
    var id: String { rawValue }
}

struct BrowserSplit: Codable, Identifiable, Equatable {
    enum Direction: String, Codable { case horizontal, vertical }
    var id = UUID()
    var tabIDs: [UUID]
    var direction = Direction.horizontal
    var fractions: [Double]
    init(tabIDs: [UUID]) {
        self.tabIDs = tabIDs
        fractions = tabIDs.map { _ in 1 / Double(tabIDs.count) }
    }
}
