import Foundation

/// What an auxiliary click on a sidebar tab row asks for, read off the row's
/// placement, and how the row performs it.
///
/// A current tab is a session member, so dismissing it means closing it. A
/// pinned or saved tab outlives the session and only its page can be put away,
/// which makes the same gesture an unload rather than a delete.
struct BrowserTabMiddleClickAction: Equatable, Sendable {
    // MARK: - Static Variables

    static let close = Self(name: "close", isDurable: false) { row in
        row.browser.closeTab(row.tab.id, matching: row.assignment)
    }
    static let unload = Self(name: "unload", isDurable: true) { row in
        guard row.isLoaded else { return }
        row.context.unload(row.tab.id)
    }

    static let all: [BrowserTabMiddleClickAction] = [close, unload]

    // MARK: - Variables

    let name: String
    /// Whether the action is the one for a placement that outlives the session.
    private let isDurable: Bool
    private let performance: @MainActor @Sendable (BrowserSidebarTabRowConfiguration) -> Void

    // MARK: - Initializers

    private init(
        name: String, isDurable: Bool,
        perform: @escaping @MainActor @Sendable (BrowserSidebarTabRowConfiguration) -> Void
    ) {
        self.name = name
        self.isDurable = isDurable
        performance = perform
    }

    /// The action an auxiliary click asks for on a tab in `placement`.
    init(for placement: TabPlacement) {
        self = Self.all.first { $0.isDurable == placement.isDurable } ?? .close
    }

    // MARK: - Actions - Performing

    /// Performs the action on the tab `row` draws.
    @MainActor
    func perform(on row: BrowserSidebarTabRowConfiguration) {
        performance(row)
    }

    // MARK: - Actions - Equality

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}
