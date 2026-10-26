/// What a mouse button press does where the pointer is: moves the page under
/// it, switches the window's Space, or is taken with nothing done.
struct BrowserSidebarMouseButtonDisposition: Equatable {
    // MARK: - Types

    /// How a disposition takes a press of `action` on the view that took it,
    /// over `page`, the page under the pointer if any.
    typealias Taking =
        @MainActor (
            BrowserSidebarMouseButtonAction, BrowserSidebarPointerNavigationView,
            (any BrowserSidebarMouseNavigationTarget)?
        ) -> Void

    // MARK: - Static Variables

    static let consume = Self(name: "consume", action: nil) { _, _, _ in }

    // MARK: - Variables

    let name: String
    let action: BrowserSidebarMouseButtonAction?
    private let taking: Taking

    // MARK: - Initializers

    private init(name: String, action: BrowserSidebarMouseButtonAction?, taking: @escaping Taking) {
        self.name = name
        self.action = action
        self.taking = taking
    }

    static func navigatePage(_ action: BrowserSidebarMouseButtonAction) -> Self {
        Self(name: "navigatePage", action: action) { action, view, page in view.navigate(action, in: page) }
    }

    static func switchSpace(_ action: BrowserSidebarMouseButtonAction) -> Self {
        Self(name: "switchSpace", action: action) { action, view, _ in view.perform(action) }
    }

    // MARK: - Actions - Taking

    /// Takes the press on `view`, over `page`.
    @MainActor
    func take(on view: BrowserSidebarPointerNavigationView, page: (any BrowserSidebarMouseNavigationTarget)?) {
        guard let action else { return }
        taking(action, view, page)
    }

    // MARK: - Actions - Equality

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name && lhs.action == rhs.action
    }
}
