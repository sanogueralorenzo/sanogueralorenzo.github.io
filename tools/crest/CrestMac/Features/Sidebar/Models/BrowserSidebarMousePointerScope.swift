/// What the pointer is over when a mouse button is pressed, and what a press
/// there does.
struct BrowserSidebarMousePointerScope: Equatable, Sendable {
    // MARK: - Types

    /// The disposition of a press of an action where the page under the
    /// pointer can or cannot move that way.
    typealias Disposing =
        @Sendable (BrowserSidebarMouseButtonAction, Bool) -> BrowserSidebarMouseButtonDisposition?

    // MARK: - Static Variables

    /// A page: a press moves it, or is taken when it cannot move that way.
    static let webpage = Self(name: "webpage") { action, canNavigatePage in
        canNavigatePage ? .navigatePage(action) : .consume
    }
    /// The sidebar: a press switches the window's Space.
    static let sidebar = Self(name: "sidebar") { action, _ in .switchSpace(action) }
    /// Neither: the press is left for others.
    static let unowned = Self(name: "unowned") { _, _ in nil }

    // MARK: - Variables

    let name: String
    private let disposing: Disposing

    // MARK: - Initializers

    private init(name: String, disposing: @escaping Disposing) {
        self.name = name
        self.disposing = disposing
    }

    // MARK: - Actions - Disposition

    /// What a press of `action` does here, where the page under the pointer
    /// `canNavigatePage` that way or not; nil where it is left for others.
    func disposition(
        for action: BrowserSidebarMouseButtonAction, canNavigatePage: Bool
    ) -> BrowserSidebarMouseButtonDisposition? {
        disposing(action, canNavigatePage)
    }

    // MARK: - Actions - Equality

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}
