/// Switches content blocking for the Space of the page the window shows, and
/// brings resident pages in line with it.
@MainActor
struct MobileContentBlockingAction {
    // MARK: - Variables

    private let browser: BrowserStore
    private let pageAssignment: () -> BrowserTabRuntimeAssignment?
    private let reconcile: () async -> Void

    // MARK: - Initializers

    init(
        browser: BrowserStore,
        pages: any MobilePageActions
    ) {
        self.browser = browser
        pageAssignment = { pages.pageAssignment }
        reconcile = { await pages.reconcileContentBlocking() }
    }

    // MARK: - Actions - Switching

    /// Switches the policy while the page the action was built for is still
    /// the one the window shows, answering whether it did.
    @discardableResult
    func perform() async -> Bool {
        guard let assignment = pageAssignment(), browser.shownTabAssignment == assignment,
            let space = browser.shownSpace
        else { return false }
        var preferences = space.settings.browsingPreferences
        preferences.contentBlocking = preferences.contentBlocking.switched
        browser.updateBrowsingPreferences(preferences, in: space.id)
        await reconcile()
        return true
    }
}
