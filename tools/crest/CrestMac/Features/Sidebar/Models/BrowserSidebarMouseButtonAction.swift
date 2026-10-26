import CoreGraphics

/// A mouse's Back or Forward button, or a swipe no page took, with what it
/// does: moves the page under the pointer through its history, or the window
/// to its neighbouring Space.
struct BrowserSidebarMouseButtonAction: Equatable, Sendable {
    // MARK: - Static Variables

    static let previousSpace = Self(
        name: "previousSpace", buttonNumber: 3, swipeSign: 1, spaceDirection: .previous,
        canNavigate: { $0.live.canGoBack }, navigate: { $0.goBack() })
    static let nextSpace = Self(
        name: "nextSpace", buttonNumber: 4, swipeSign: -1, spaceDirection: .next,
        canNavigate: { $0.live.canGoForward }, navigate: { $0.goForward() })

    static let all: [BrowserSidebarMouseButtonAction] = [previousSpace, nextSpace]

    // MARK: - Variables

    let name: String
    /// The mouse button that asks for the action.
    let buttonNumber: Int
    /// The sign of a swipe's `deltaX` that asks for the action.
    let swipeSign: CGFloat
    /// The way the action steps through the window's Spaces.
    let spaceDirection: BrowserSpaceSwipeDirection
    private let canNavigatePage: @MainActor @Sendable (any BrowserSidebarMouseNavigationTarget) -> Bool
    private let navigatePage: @MainActor @Sendable (any BrowserSidebarMouseNavigationTarget) -> Void

    // MARK: - Initializers

    private init(
        name: String, buttonNumber: Int, swipeSign: CGFloat, spaceDirection: BrowserSpaceSwipeDirection,
        canNavigate: @escaping @MainActor @Sendable (any BrowserSidebarMouseNavigationTarget) -> Bool,
        navigate: @escaping @MainActor @Sendable (any BrowserSidebarMouseNavigationTarget) -> Void
    ) {
        self.name = name
        self.buttonNumber = buttonNumber
        self.swipeSign = swipeSign
        self.spaceDirection = spaceDirection
        canNavigatePage = canNavigate
        navigatePage = navigate
    }

    /// The action mouse button `buttonNumber` asks for, if any.
    init?(buttonNumber: Int) {
        guard let action = Self.all.first(where: { $0.buttonNumber == buttonNumber }) else { return nil }
        self = action
    }

    /// A swipe no page took goes back when it moves right, a positive
    /// `deltaX`, and forward when it moves left, as WebKit's views and
    /// Chrome's windows read it. A vertical swipe does neither.
    init?(swipeDeltaX deltaX: CGFloat) {
        guard let action = Self.all.first(where: { $0.swipeSign * deltaX > 0 }) else { return nil }
        self = action
    }

    // MARK: - Actions - Navigation

    /// Whether `page` can move the way the action asks.
    @MainActor
    func canNavigate(_ page: any BrowserSidebarMouseNavigationTarget) -> Bool {
        canNavigatePage(page)
    }

    /// Moves `page` the way the action asks.
    @MainActor
    func navigate(_ page: any BrowserSidebarMouseNavigationTarget) {
        navigatePage(page)
    }

    // MARK: - Actions - Equality

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}
