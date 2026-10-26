import SwiftUI

/// The pages of one Space in Settings, in the order its tab bar shows them.
struct BrowserSpaceSettingsTab: Hashable, Identifiable, Sendable {
    // MARK: - Types

    /// Each page shows its own pane. ``BrowserSettingsSpacePage`` switches on
    /// the kind to choose that pane's concrete view.
    enum Kinds: Sendable {
        case appearance
        case browsing
        case privacy
        case passwords
        case extensions
    }

    // MARK: - Static Variables

    static let appearance = BrowserSpaceSettingsTab(
        kind: .appearance, name: "appearance", title: "Appearance",
        searchTerms: "crest studio name icon emblem colors theme banner background sidebar pattern gradient accent",
        destination: .spaces)
    static let browsing = BrowserSpaceSettingsTab(
        kind: .browsing, name: "browsing", title: "Browsing",
        searchTerms: "search engine suggestions archive tabs cleanup downloads folder save location delete Space")
    static let privacy = BrowserSpaceSettingsTab(
        kind: .privacy, name: "privacy", title: "Privacy",
        searchTerms:
            "privacy lock Touch ID password private history retention archive downloads records content blocking ads trackers site permissions camera microphone location notifications"
    )
    static let passwords = BrowserSpaceSettingsTab(
        kind: .passwords, name: "passwords", title: "Passwords",
        searchTerms: "passwords credentials autofill iCloud Keychain import export", destination: .passwords)
    static let extensions = BrowserSpaceSettingsTab(
        kind: .extensions, name: "extensions", title: "Extensions",
        searchTerms: "extensions add-ons Chrome Web Store install remove", destination: .extensions,
        requiredCapability: .extensions)

    /// Every page, in tab-bar order.
    static let all: [BrowserSpaceSettingsTab] = [appearance, browsing, privacy, passwords, extensions]

    // MARK: - Variables

    let kind: Kinds
    let name: String
    let title: LocalizedStringResource

    /// Words that find this page from the Settings search field.
    let searchTerms: LocalizedStringResource

    /// The settings destination whose subject this page holds for one Space,
    /// so a request for that destination opens this page instead.
    let destination: BrowserSettingsDestination?

    /// The engine capability the page's subject depends on.
    let requiredCapability: EngineCapability?

    var id: String { name }

    // MARK: - Initializers

    private init(
        kind: Kinds, name: String, title: LocalizedStringResource, searchTerms: LocalizedStringResource,
        destination: BrowserSettingsDestination? = nil, requiredCapability: EngineCapability? = nil
    ) {
        self.kind = kind
        self.name = name
        self.title = title
        self.searchTerms = searchTerms
        self.destination = destination
        self.requiredCapability = requiredCapability
    }

    // MARK: - Actions - Lookup

    /// The page that holds `destination` for one Space, if it has one.
    static func holding(_ destination: BrowserSettingsDestination) -> BrowserSpaceSettingsTab? {
        all.first { $0.destination == destination }
    }

    static func named(_ name: String) -> BrowserSpaceSettingsTab? {
        all.first { $0.name == name }
    }

    /// Whether this page exists for the engines the device runs.
    @MainActor
    func isProvided(in state: CoreState) -> Bool {
        requiredCapability.map(state.offers) ?? true
    }

    /// The tabs the device offers, in order.
    @MainActor
    static func provided(in state: CoreState) -> [BrowserSpaceSettingsTab] {
        all.filter { $0.isProvided(in: state) }
    }

    /// The first tab whose words match a search, if any.
    @MainActor
    static func matching(_ query: String, locale: Locale, in state: CoreState) -> BrowserSpaceSettingsTab? {
        provided(in: state).first { tab in
            [tab.title, tab.searchTerms].contains { resource in
                var resource = resource
                resource.locale = locale
                return String(localized: resource).localizedStandardContains(query)
            }
        }
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSpaceSettingsTab, rhs: BrowserSpaceSettingsTab) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

/// What a route into a Space's page asks it to do on arrival.
enum BrowserSettingsSpaceIntent: Equatable, Sendable {
    case none
    /// Put the Space's name into editing.
    case rename
    /// A Space just made: name it, then pick where its crest starts.
    case newSpace
}
