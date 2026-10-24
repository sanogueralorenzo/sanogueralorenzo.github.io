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
        case tabs
        case search
        case engines
        case lookAndFeel
        case links
        case shortcuts
        case spaces
        case sync
        case privacy
        case passwords
        case extensions
        case featureFlags
        case advanced
        case about
        case agents
    }

    // MARK: - Static Variables

    // Each destination wears a template tincture: the templates' main colors
    // first, in list order, then their other colors, so neighbouring rows never
    // share a hue on either platform and read the same in both appearances.
    static let general = BrowserSettingsDestination(
        kind: .general, name: "general", title: "General", subtitle: "Browsing and startup",
        searchTerms:
            "browser startup default Space typing spelling spell check text editing Picture in Picture video developer toolbar localhost local pages translation system permissions access camera microphone location notifications passkeys files folders downloads allow blocked repair new tab floating sidebar",
        symbol: "gearshape", tincture: .vigilAsh)
    static let tabs = BrowserSettingsDestination(
        kind: .tabs, name: "tabs", title: "Tabs", subtitle: "New, pinned and saved tabs",
        searchTerms:
            "focus switch new tabs follow move between Spaces Command-click middle-click Shift pinned saved close resume restore root URL favicon Split View focus follows mouse pointer sidebar widgets Now Playing media cards",
        symbol: "square.on.square", tincture: .riverAzure)
    static let search = BrowserSettingsDestination(
        kind: .search, name: "search", title: "Search", subtitle: "Search engine, command palette and site searches",
        searchTerms:
            "search engine Google suggestions command palette address bar results order top hit blended sections complete addresses inline autocomplete learn choices clear site searches shortcuts Tab YouTube Wikipedia scopes calculator paste and go reasons",
        symbol: "magnifyingglass", tincture: .sunTenne)
    static let lookAndFeel = BrowserSettingsDestination(
        kind: .lookAndFeel, name: "lookAndFeel", title: "Appearance", subtitle: "Window, tabs, zoom and motion",
        searchTerms:
            "look and feel theme accent color transparency page zoom percentage sidebar left right borderless window fullscreen layout interface animation motion page cards folder highlights counts borders preview density spacing padding scale icons space size fit automatic",
        symbol: "paintpalette", tincture: .lionGules)
    static let engines = BrowserSettingsDestination(
        kind: .engines, name: "engines", title: "Engines", subtitle: "Default engine and website rules",
        searchTerms: "Chromium WebKit hybrid default browser engine websites rules protected video DRM compatibility",
        symbol: "cpu", tincture: .riverLapis, isMacOnly: true)
    static let links = BrowserSettingsDestination(
        kind: .links, name: "links", title: "Links", subtitle: "Quick Window and Peek",
        searchTerms: "external apps Quick Window Peek pinned saved routing open", symbol: "link",
        tincture: .meadowVert)
    static let shortcuts = BrowserSettingsDestination(
        kind: .shortcuts, name: "shortcuts", title: "Shortcuts", subtitle: "Keyboard commands",
        searchTerms: "keyboard keys commands rebind remap Arc hotkeys navigation tabs Spaces page", symbol: "keyboard",
        tincture: .lionOr, isMacOnly: true)
    static let spaces = BrowserSettingsDestination(
        kind: .spaces, name: "spaces", title: "Spaces", subtitle: "Profiles and appearance",
        searchTerms:
            "profile name identity icon color appearance theme search cleanup isolation reorder browsing archive independence folder intensity text color light dark automatic preview",
        symbol: "square.grid.2x2", tincture: .stormOr)
    static let sync = BrowserSettingsDestination(
        kind: .sync, name: "sync", title: "Sync", subtitle: "iCloud setup and status",
        searchTerms: "iCloud CloudKit account upload download conflict status monitor diagnostics pending records",
        symbol: "arrow.triangle.2.circlepath.icloud", tincture: .winterIce)
    // The macOS sidebar row cannot fit "Privacy & Permissions" on one line at
    // its compact row height.
    static let privacy = BrowserSettingsDestination(
        kind: .privacy, name: "privacy", title: "Privacy & Permissions", navigationTitle: "Privacy",
        subtitle: "Site access and data",
        searchTerms: "content blocking ads trackers camera microphone site access history cookies data",
        symbol: "hand.raised", tincture: .dragonFire)
    static let passwords = BrowserSettingsDestination(
        kind: .passwords, name: "passwords", title: "Passwords", subtitle: "Credentials and autofill",
        searchTerms: "credentials autofill iCloud Keychain passkeys synchronization", symbol: "key",
        tincture: .ironPatina)
    static let extensions = BrowserSettingsDestination(
        kind: .extensions, name: "extensions", title: "Extensions", subtitle: "Space extensions and permissions",
        searchTerms: "extensions permissions Chromium Chrome Web Store install copies Spaces",
        symbol: "puzzlepiece.extension", tincture: .meadowMoss,
        requiredCapability: .extensions)
    static let featureFlags = BrowserSettingsDestination(
        kind: .featureFlags, name: "featureFlags", title: "Feature Flags", subtitle: "Engine experiments",
        searchTerms: "WebKit Chromium experimental preview testable developer stable runtime flags features",
        symbol: "flag.2.crossed", tincture: .sunTerracotta, isMacOnly: true,
        requiredCapability: .featureFlags)
    static let advanced = BrowserSettingsDestination(
        kind: .advanced, name: "advanced", title: "Advanced", subtitle: "Import, export, and runtime",
        searchTerms: "import export backup portability data records", symbol: "switch.2",
        tincture: .stormGunmetal)
    static let agents = BrowserSettingsDestination(
        kind: .agents, name: "agents", title: "Agents", subtitle: "Coding agents and scripts",
        searchTerms:
            "agents AI MCP model context protocol coding agents scripts automation Claude Codex Cursor command line terminal",
        symbol: "sparkles", tincture: .meadowForest, isMacOnly: true)
    static let about = BrowserSettingsDestination(
        kind: .about, name: "about", title: "About", subtitle: "Version, updates, and support",
        searchTerms:
            "version build updates changelog what's new feedback Reddit GitHub issues roadmap support community",
        symbol: "info.circle", tincture: .sunDune)

    /// Every destination, in catalog order.
    static let all: [BrowserSettingsDestination] = [
        general, tabs, search, engines, lookAndFeel, links, shortcuts, spaces, sync, privacy, passwords, extensions,
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

    /// The template tincture that stands for the destination: the fill of
    /// its tile, or its glyph's tint where the glyph is not tiled.
    let tincture: Tincture

    /// The tincture's color, which fills the destination's tile.
    var color: Color { tincture.color.color }

    /// The engine capability the destination's whole subject depends on. An
    /// engine without it never offers the destination.
    let requiredCapability: EngineCapability?

    /// Whether the subject exists only on the Mac: the engine choice,
    /// rebindable keyboard commands and WebKit's private feature registry.
    let isMacOnly: Bool

    var id: String { name }

    // MARK: - Initializers

    private init(
        kind: Kinds, name: String, title: LocalizedStringResource, navigationTitle: LocalizedStringResource? = nil,
        subtitle: LocalizedStringResource, searchTerms: LocalizedStringResource, symbol: String,
        tincture: Tincture, isMacOnly: Bool = false, requiredCapability: EngineCapability? = nil
    ) {
        self.kind = kind
        self.name = name
        self.title = title
        self.navigationTitle = navigationTitle ?? title
        self.subtitle = subtitle
        self.searchTerms = searchTerms
        self.symbol = symbol
        self.tincture = tincture
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
