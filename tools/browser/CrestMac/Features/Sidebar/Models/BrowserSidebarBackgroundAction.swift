import Foundation

/// What the empty sidebar's context menu offers.
struct BrowserSidebarBackgroundAction: Hashable, Identifiable, Sendable {
    // MARK: - Static Variables

    static let editSpace = BrowserSidebarBackgroundAction(
        name: "editSpace", title: "Edit Space…", symbol: "pencil", requiresSpaceCreation: false
    ) { $0.editSpace() }
    static let newSpace = BrowserSidebarBackgroundAction(
        name: "newSpace", title: "New Space…", symbol: "plus", requiresSpaceCreation: true
    ) { $0.createSpace?() }

    /// Every action, in menu order.
    static let all: [BrowserSidebarBackgroundAction] = [editSpace, newSpace]

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource
    let symbol: String

    /// Whether the menu offers the action only where the sidebar can create
    /// Spaces.
    let requiresSpaceCreation: Bool
    private let performance: @MainActor @Sendable (BrowserSidebarBackgroundInteractionView) -> Void

    var id: String { name }

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, symbol: String, requiresSpaceCreation: Bool,
        perform: @escaping @MainActor @Sendable (BrowserSidebarBackgroundInteractionView) -> Void
    ) {
        self.name = name
        self.title = title
        self.symbol = symbol
        self.requiresSpaceCreation = requiresSpaceCreation
        performance = perform
    }

    // MARK: - Actions - Performing

    /// Performs the action through the sidebar background `view` it was
    /// chosen on.
    @MainActor
    func perform(on view: BrowserSidebarBackgroundInteractionView) {
        performance(view)
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSidebarBackgroundAction, rhs: BrowserSidebarBackgroundAction) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
