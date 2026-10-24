/// Where a narrow window is between its tab viewer and its page.
struct MobileCompactPagePresentationPhase: Equatable {
    // MARK: - Static Variables

    /// The full-screen tab viewer, with no page over it.
    static let tabViewer = MobileCompactPagePresentationPhase(name: "tabViewer", showsPage: false)
    /// The page coming up over the tab viewer.
    static let presentingPage = MobileCompactPagePresentationPhase(name: "presentingPage", showsPage: true)
    /// The page, fully presented.
    static let page = MobileCompactPagePresentationPhase(name: "page", showsPage: true)

    // MARK: - Variables

    let name: String
    /// Whether the page is on screen, coming up or fully presented.
    let showsPage: Bool

    // MARK: - Initializers

    private init(name: String, showsPage: Bool) {
        self.name = name
        self.showsPage = showsPage
    }
}
