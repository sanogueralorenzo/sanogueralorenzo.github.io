import Foundation

struct BrowserAboutBuildInformation: Equatable, Sendable {
    let version: String
    let build: String
    let bundleIdentifier: String

    static let current = BrowserAboutBuildInformation(bundle: .main)

    init(bundle: Bundle) {
        self.init(
            infoDictionary: bundle.infoDictionary ?? [:],
            bundleIdentifier: bundle.bundleIdentifier
        )
    }

    init(
        infoDictionary: [String: Any],
        bundleIdentifier: String?
    ) {
        version = infoDictionary["CFBundleShortVersionString"] as? String ?? "—"
        build = infoDictionary["CFBundleVersion"] as? String ?? "—"
        self.bundleIdentifier =
            bundleIdentifier ?? ProductIdentity.bundleIdentifier
    }
}

enum BrowserAboutLinks {
    static var feedback: URL {
        url("https://www.reddit.com/r/CrestBrowser")
    }

    static var issues: URL {
        url("https://github.com/pauljoda/Crest/issues/new/choose")
    }

    /// Where to ask Crest to import from a browser it does not list.
    static var browserRequest: URL {
        url("https://github.com/pauljoda/Crest/issues/new?template=feature_request.yml&title=Import%20from%20")
    }

    static var roadmap: URL {
        url("https://github.com/users/pauljoda/projects/3")
    }

    private static func url(_ value: String) -> URL {
        guard let url = URL(string: value) else {
            preconditionFailure("Invalid About link: \(value)")
        }
        return url
    }
}

enum BrowserAboutReleaseNoteCategory: String, Decodable, Sendable {
    case new
    case improved
    case fixed
    case `internal`
}

struct BrowserAboutReleaseNote: Equatable, Identifiable, Sendable {
    let id: String
    let category: BrowserAboutReleaseNoteCategory
    let message: String
}

struct BrowserAboutReleaseNotes: Sendable {
    private struct Document: Decodable {
        let entries: [String: Entry]
    }

    private struct Entry: Decodable {
        let category: BrowserAboutReleaseNoteCategory
        let message: String
    }

    private(set) var entries: [BrowserAboutReleaseNote]

    static let bundled = loadBundled()

    init(data: Data) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        entries = document.entries.map { id, entry in
            BrowserAboutReleaseNote(
                id: id,
                category: entry.category,
                message: entry.message
            )
        }
    }

    init(entries: [BrowserAboutReleaseNote]) {
        self.entries = entries
    }

    func currentHighlights(limit: Int = 12) -> [BrowserAboutReleaseNote] {
        guard limit > 0 else { return [] }
        return Array(
            entries
                .filter { $0.category != .internal }
                .sorted { $0.id > $1.id }
                .prefix(limit)
        )
    }

    private static func loadBundled() -> BrowserAboutReleaseNotes {
        guard
            let url = Bundle.main.url(
                forResource: "ReleaseNotes",
                withExtension: "json"
            ),
            let data = try? Data(contentsOf: url),
            let releaseNotes = try? BrowserAboutReleaseNotes(data: data)
        else {
            return BrowserAboutReleaseNotes(entries: [])
        }
        return releaseNotes
    }
}
