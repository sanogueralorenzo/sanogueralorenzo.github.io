import Foundation

/// The browser and pages a Quick Window promotes into, and whether its live
/// page can move there.
struct BrowserQuickWindowBrowsingContext {
    // MARK: - Variables

    let browser: BrowserStore
    let pages: BrowserPagePool
    let supportsLivePagePromotion: Bool

    // MARK: - Initializers

    init(browser: BrowserStore, pages: BrowserPagePool, supportsLivePagePromotion: Bool) {
        self.browser = browser
        self.pages = pages
        self.supportsLivePagePromotion = supportsLivePagePromotion
    }

    /// The context `request` opens in, or nil when its window is gone or its
    /// Space no longer exists there. `browser` and `pages` are the shared
    /// workspace's.
    @MainActor
    init?(
        for request: BrowserQuickWindowRequest, browser: BrowserStore, pages: BrowserPagePool,
        pagePoolRegistry: BrowserPagePoolRegistry
    ) {
        guard
            let context = Self(
                targetWindowID: request.targetWindowID, browser: browser, pages: pages,
                pagePoolRegistry: pagePoolRegistry),
            context.browser.spaceModel(matching: request.assignment) != nil
        else {
            return nil
        }
        self = context
    }

    /// The context of the window `targetWindowID` names, or of the shared
    /// workspace when it names none; nil when that window is gone.
    @MainActor
    init?(
        targetWindowID: UUID?, browser: BrowserStore, pages: BrowserPagePool,
        pagePoolRegistry: BrowserPagePoolRegistry
    ) {
        guard let targetWindowID else {
            self.init(browser: browser, pages: pages, supportsLivePagePromotion: false)
            return
        }
        guard let runtime = pagePoolRegistry.runtime(for: targetWindowID) else {
            return nil
        }
        // Blank windows own disposable tabs. A Quick Window opened from one
        // promotes into the shared workspace, never back into that blank window.
        if runtime.browser.isTemporaryWorkspace {
            self.init(browser: browser, pages: pages, supportsLivePagePromotion: false)
            return
        }
        self.init(browser: runtime.browser, pages: runtime.pages, supportsLivePagePromotion: true)
    }
}
