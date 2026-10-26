import Foundation

/// One action on the tabs and folders a window's sidebar selected: the intent
/// the window sends the core, and what the window does once the core accepts
/// it. `BrowserStore` makes one for each action; see `BrowserStore+TabBatch`.
struct BrowserTabBatch {
    // MARK: - Variables

    let intent: any Intent
    /// What the window's multi-selection holds once the action is done.
    let reselection: BrowserTabReselection
    /// Whether the action closes the selected tabs' pages, which may first
    /// ask the person to leave them.
    let closesPages: Bool
    /// The Space the window follows the tabs to, when it does.
    let following: BrowserSpaceRuntimeAssignment?

    // MARK: - Initializers

    init(
        _ intent: any Intent, reselection: BrowserTabReselection, closesPages: Bool = false,
        following: BrowserSpaceRuntimeAssignment? = nil
    ) {
        self.intent = intent
        self.reselection = reselection
        self.closesPages = closesPages
        self.following = following
    }
}
