import SwiftUI

/// The one settings catalog both shells navigate.
///
/// macOS presents these in a `NavigationSplitView` sidebar; iOS presents them in a
/// `NavigationSplitView` or `NavigationStack` sheet. Each shell keeps its own
/// navigation and pane content — this type owns only the *identity* of a
/// destination: what it is called, how it is described, which glyph and brand
/// hue stand for it, and which words find it in search.
///
/// `name` is a shipped contract: accessibility identifiers derive from it
/// (`settings-<name>` rows and `settings-form-<name>` forms), so the names
/// below cannot change without breaking the automation suites.
struct BrowserSettingsDestination: Hashable, Identifiable, Sendable {
    // MARK: - Types

    /// Each destination opens its own pane. ``BrowserSettingsDestinationRouter``
    /// switches on the kind to choose that pane's concrete view.
    enum Kinds: Sendable {
        case general
        case engines
        case spaces
        case sync
        case privacy
        case extensions
        case featureFlags
        case advanced
        case about
        case agents
    }

    // MARK: - Static Variables

    static let general = BrowserSettingsDestination(
        kind: .general, name: "general", title: "General", subtitle: "Browsing",
        searchTerms:
            "search provider Google DuckDuckGo Bing Brave zoom default browser translate translation language floating sidebar",
        symbol: "gearshape")
    static let engines = BrowserSettingsDestination(
        kind: .engines, name: "engines", title: "Engines", subtitle: "Default browsing engine",
        searchTerms: "Chromium WebKit hybrid default browser engine protected video DRM compatibility",
        symbol: "cpu", isMacOnly: true)
    static let spaces = BrowserSettingsDestination(
        kind: .spaces, name: "spaces", title: "Spaces", subtitle: "Profiles and browsing",
        searchTerms:
            "profile name identity initial letter search isolation reorder browsing independence",
        symbol: "square.grid.2x2")
    static let sync = BrowserSettingsDestination(
        kind: .sync, name: "sync", title: "Sync", subtitle: "iCloud setup and status",
        searchTerms: "iCloud CloudKit account upload download conflict status monitor diagnostics pending records",
        symbol: "arrow.triangle.2.circlepath.icloud")
    // The macOS sidebar row cannot fit "Privacy & Permissions" on one line at
    // its compact row height.
    static let privacy = BrowserSettingsDestination(
        kind: .privacy, name: "privacy", title: "Privacy & Permissions", navigationTitle: "Privacy",
        subtitle: "Site access and data",
        searchTerms: "content blocking ads trackers camera microphone site access history cookies data",
        symbol: "hand.raised")

    static let extensions = BrowserSettingsDestination(
        kind: .extensions, name: "extensions", title: "Extensions", subtitle: "Space extensions and permissions",
        searchTerms: "extensions permissions Chromium Chrome Web Store install copies Spaces",
        symbol: "puzzlepiece.extension",
        requiredCapability: .extensions)
    static let featureFlags = BrowserSettingsDestination(
        kind: .featureFlags, name: "featureFlags", title: "Feature Flags", subtitle: "Engine experiments",
        searchTerms: "WebKit Chromium experimental preview testable developer stable runtime flags features",
        symbol: "flag.2.crossed", isMacOnly: true,
        requiredCapability: .featureFlags)
    static let advanced = BrowserSettingsDestination(
        kind: .advanced, name: "advanced", title: "Advanced", subtitle: "Import, export, and runtime",
        searchTerms: "import export backup portability data records", symbol: "switch.2")
    static let agents = BrowserSettingsDestination(
        kind: .agents, name: "agents", title: "Agents", subtitle: "Coding agents and scripts",
        searchTerms:
            "agents AI MCP model context protocol coding agents scripts automation Claude Codex Cursor command line terminal",
        symbol: "sparkles", isMacOnly: true)
    static let about = BrowserSettingsDestination(
        kind: .about, name: "about", title: "About", subtitle: "Version, updates, and support",
        searchTerms:
            "version build updates changelog what's new feedback Reddit GitHub issues roadmap support community",
        symbol: "info.circle")

    /// Every destination, in catalog order.
    static let all: [BrowserSettingsDestination] = [
        general, engines, spaces, sync, privacy, extensions,
        featureFlags, agents, advanced, about,
    ]

    // MARK: - Variables

    let kind: Kinds
    let name: String
    let title: LocalizedStringResource

    /// The title where space is tight enough that the full name wraps.
    let navigationTitle: LocalizedStringResource

    let subtitle: LocalizedStringResource

    /// Localized vocabulary that supplements the visible destination metadata.
    ///
    /// The terms are the union of the vocabulary each platform used before this
    /// catalog was shared, so neither shell loses a search route.
    let searchTerms: LocalizedStringResource

    let symbol: String

    /// Monochrome tint for settings navigation.
    var color: Color { CrestBrandTheme.textDisplay }

    /// The engine capability the destination's whole subject depends on. An
    /// engine without it never offers the destination.
    let requiredCapability: EngineCapability?

    /// Whether the subject exists only on the Mac: the engine choice,
    /// and WebKit's private feature registry.
    let isMacOnly: Bool

    var id: String { name }

    // MARK: - Initializers

    private init(
        kind: Kinds, name: String, title: LocalizedStringResource, navigationTitle: LocalizedStringResource? = nil,
        subtitle: LocalizedStringResource, searchTerms: LocalizedStringResource, symbol: String,
        isMacOnly: Bool = false, requiredCapability: EngineCapability? = nil
    ) {
        self.kind = kind
        self.name = name
        self.title = title
        self.navigationTitle = navigationTitle ?? title
        self.subtitle = subtitle
        self.searchTerms = searchTerms
        self.symbol = symbol
        self.isMacOnly = isMacOnly
        self.requiredCapability = requiredCapability
    }

    // MARK: - Actions - Platform capability

    /// The destinations this platform can present, in catalog order, whose
    /// subject the device offers.
    ///
    /// Shells iterate this rather than `all` so a destination that only one
    /// platform can host stays out of the other's list.
    @MainActor
    static func platformCases(in state: CoreState) -> [BrowserSettingsDestination] {
        BrowserPlatformSettingsDestinationCatalog.cases.filter { $0.isProvided(in: state) }
    }

    /// Whether the device offers the destination's subject at all: the
    /// default engine or an engine a page is open on provides it.
    ///
    /// The set is fixed: accessibility identifiers derive from it and the
    /// automation suites pin it, so a destination never disappears from the
    /// catalog because of which engines this process registered. Only its
    /// availability follows what they offer.
    @MainActor
    func isProvided(in state: CoreState) -> Bool {
        requiredCapability.map(state.offers) ?? true
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSettingsDestination, rhs: BrowserSettingsDestination) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
