import Foundation

struct BrowserWebKitFeatureFlag: Identifiable, Equatable, Sendable {
    let key: String
    let name: String
    let details: String
    let status: BrowserWebKitFeatureStatus
    let category: BrowserWebKitFeatureCategory
    let defaultValue: Bool

    var id: String { key }

    var searchText: String {
        [name, key, details, status.title, category.title]
            .joined(separator: " ")
    }
}

/// How far along WebKit says a feature is, by the status number WebKit gives
/// it.
struct BrowserWebKitFeatureStatus: Identifiable, Hashable, Sendable {
    // MARK: - Static Variables

    static let embedder = BrowserWebKitFeatureStatus(rawValue: 0, title: "Embedder")
    static let unstable = BrowserWebKitFeatureStatus(rawValue: 1, title: "Unstable")
    static let `internal` = BrowserWebKitFeatureStatus(rawValue: 2, title: "Internal")
    static let developer = BrowserWebKitFeatureStatus(rawValue: 3, title: "Developer")
    static let testable = BrowserWebKitFeatureStatus(rawValue: 4, title: "Testable")
    static let preview = BrowserWebKitFeatureStatus(rawValue: 5, title: "Preview")
    static let stable = BrowserWebKitFeatureStatus(rawValue: 6, title: "Stable")
    static let mature = BrowserWebKitFeatureStatus(rawValue: 7, title: "Mature")

    /// Every status WebKit is known to give, least finished first.
    static let all: [BrowserWebKitFeatureStatus] = [
        embedder, unstable, `internal`, developer, testable, preview, stable, mature,
    ]

    // MARK: - Variables

    let rawValue: Int
    let title: String

    var id: Int { rawValue }

    // MARK: - Initializers

    /// The status WebKit's number names, or one titled Other for a number a
    /// newer WebKit adds.
    init(rawValue: Int) {
        self = Self.all.first { $0.rawValue == rawValue } ?? Self(rawValue: rawValue, title: "Other")
    }

    private init(rawValue: Int, title: String) {
        self.rawValue = rawValue
        self.title = title
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserWebKitFeatureStatus, rhs: BrowserWebKitFeatureStatus) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

/// The area of the web platform a WebKit feature belongs to, by the category
/// number WebKit gives it.
struct BrowserWebKitFeatureCategory: Identifiable, Hashable, Sendable {
    // MARK: - Static Variables

    static let animation = BrowserWebKitFeatureCategory(rawValue: 1, title: "Animation")
    static let css = BrowserWebKitFeatureCategory(rawValue: 2, title: "CSS")
    static let dom = BrowserWebKitFeatureCategory(rawValue: 3, title: "DOM")
    static let extensions = BrowserWebKitFeatureCategory(rawValue: 4, title: "Extensions")
    static let html = BrowserWebKitFeatureCategory(rawValue: 5, title: "HTML")
    static let javaScript = BrowserWebKitFeatureCategory(rawValue: 6, title: "JavaScript")
    static let media = BrowserWebKitFeatureCategory(rawValue: 7, title: "Media")
    static let networking = BrowserWebKitFeatureCategory(rawValue: 8, title: "Networking")
    static let privacy = BrowserWebKitFeatureCategory(rawValue: 9, title: "Privacy")
    static let security = BrowserWebKitFeatureCategory(rawValue: 10, title: "Security")

    /// Every category WebKit is known to give, in WebKit's order.
    static let all: [BrowserWebKitFeatureCategory] = [
        animation, css, dom, extensions, html, javaScript, media, networking, privacy, security,
    ]

    // MARK: - Variables

    let rawValue: Int
    let title: String

    var id: Int { rawValue }

    // MARK: - Initializers

    /// The category WebKit's number names, or one titled Other for a number
    /// WebKit leaves uncategorized or a newer WebKit adds.
    init(rawValue: Int) {
        self = Self.all.first { $0.rawValue == rawValue } ?? Self(rawValue: rawValue, title: "Other")
    }

    private init(rawValue: Int, title: String) {
        self.rawValue = rawValue
        self.title = title
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserWebKitFeatureCategory, rhs: BrowserWebKitFeatureCategory) -> Bool {
        lhs.rawValue == rhs.rawValue
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(rawValue)
    }
}

enum BrowserWebKitFeatureFlagOverride: String, Hashable, Sendable {
    case enabled
    case disabled

    var value: Bool {
        self == .enabled
    }
}
