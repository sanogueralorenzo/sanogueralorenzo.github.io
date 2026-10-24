import AppKit

/// A command the menu bar offers beside Crest's shortcut commands, which the
/// shell runs: the application's own, under the application's and the Help
/// menus, and the few of a page's that no shortcut names.
@MainActor
struct BrowserMacApplicationAction: Hashable {
    // MARK: - Static Variables

    static let about = BrowserMacApplicationAction(name: "about", title: "About Crest") { $0.showAbout() }
    static let updates = BrowserMacApplicationAction(
        name: "updates", title: "Check for Updates…", symbol: "arrow.triangle.2.circlepath",
        isEnabled: { $0.canCheckForUpdates }, perform: { $0.checkForUpdates() })
    static let settings = BrowserMacApplicationAction(
        name: "settings", title: "Settings…", symbol: "gearshape", keyEquivalent: ","
    ) { $0.openSettings() }
    /// Ends every agent's connection and keeps agents out of the tabs they
    /// used until Crest quits, while any agent is connected.
    static let stopAllAgents = BrowserMacApplicationAction(
        name: "stop-all-agents", title: "Stop All Agents", symbol: "stop.circle",
        isEnabled: { $0.hasConnectedAgents }, perform: { $0.stopAllAgents() })
    static let gettingStarted = BrowserMacApplicationAction(
        name: "getting-started", title: "Getting Started with Crest"
    ) { $0.openGettingStarted() }
    /// Translates the whole shown page, offered while the translation toolbar
    /// is.
    static let translatePage = BrowserMacApplicationAction(
        name: "translate-page", title: "Translate Page", symbol: "translate", offeredWith: .toggleTranslationToolbar,
        isEnabled: { $0.pageActions?.canPerform(.toggleTranslationToolbar) == true },
        perform: { $0.pageActions?.translatePage() })
    static let all: [BrowserMacApplicationAction] = [
        about, updates, settings, stopAllAgents, gettingStarted, translatePage,
    ]

    // MARK: - Variables

    /// The action's name, which identifies it.
    nonisolated let name: String
    let title: LocalizedStringResource
    /// The symbol its menu item shows, or none.
    let symbol: String?
    /// The key that runs it with Command, or none.
    let keyEquivalent: String
    /// The shortcut command the device must offer for the menu to show the
    /// action, or nil when it always shows.
    let offeredWith: ShortcutCommand?
    private let availability: @MainActor (BrowserMacShell) -> Bool
    private let run: @MainActor (BrowserMacShell) -> Void

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, symbol: String? = nil, keyEquivalent: String = "",
        offeredWith: ShortcutCommand? = nil, isEnabled: @escaping @MainActor (BrowserMacShell) -> Bool = { _ in true },
        perform: @escaping @MainActor (BrowserMacShell) -> Void
    ) {
        self.name = name
        self.title = title
        self.symbol = symbol
        self.keyEquivalent = keyEquivalent
        self.offeredWith = offeredWith
        availability = isEnabled
        run = perform
    }

    // MARK: - Actions - Running

    /// Whether the menu shows the action, as the read model `state` says.
    func isOffered(in state: CoreState) -> Bool {
        offeredWith?.isOffered(in: state) ?? true
    }

    /// Whether `shell` can run the action now.
    func isEnabled(in shell: BrowserMacShell) -> Bool {
        availability(shell)
    }

    /// Runs the action in `shell`.
    func perform(in shell: BrowserMacShell) {
        run(shell)
    }
}

// MARK: - Hashable

extension BrowserMacApplicationAction {
    nonisolated static func == (lhs: BrowserMacApplicationAction, rhs: BrowserMacApplicationAction) -> Bool {
        lhs.name == rhs.name
    }

    nonisolated func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
