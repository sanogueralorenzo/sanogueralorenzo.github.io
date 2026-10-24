import Foundation

/// What the sidebar's toggle does from where the sidebar is.
struct BrowserSidebarToggleAction: Hashable, Sendable {
    // MARK: - Static Variables

    static let hide = BrowserSidebarToggleAction(
        name: "hide", title: "Hide Sidebar", performs: { $0.hideSidebar(reduceMotion: $1) })
    static let dock = BrowserSidebarToggleAction(
        name: "dock", title: "Dock Sidebar", performs: { $0.dockSidebar(reduceMotion: $1) })

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource
    private let performs: @MainActor @Sendable (any BrowserSidebarToggleTarget, Bool) -> Void

    // MARK: - Initializers

    private init(
        name: String,
        title: LocalizedStringResource,
        performs: @escaping @MainActor @Sendable (any BrowserSidebarToggleTarget, Bool) -> Void
    ) {
        self.name = name
        self.title = title
        self.performs = performs
    }

    // MARK: - Actions - Toggle

    /// Moves `target`'s sidebar where this action sends it.
    @MainActor
    func perform(on target: some BrowserSidebarToggleTarget, reduceMotion: Bool) {
        performs(target, reduceMotion)
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSidebarToggleAction, rhs: BrowserSidebarToggleAction) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
