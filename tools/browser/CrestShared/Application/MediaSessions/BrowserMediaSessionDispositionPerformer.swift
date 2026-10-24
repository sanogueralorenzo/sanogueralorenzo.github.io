import Foundation

// MARK: - Types

/// A page's report about its session that the core accepted, with what the
/// core decided to do with it.
struct BrowserMediaSessionReport {
    let id: BrowserMediaSessionID
    let event: BrowserMediaSessionPageEvent
    let owner: BrowserTabRuntimeAssignment
    let fallbackTitle: String?
    let decision: MediaSessionEventDecision
}

/// What the core's disposition of a page report asks of the store that keeps
/// the session. A disposition the core adds fails to compile until the store
/// handles it.
@MainActor
protocol BrowserMediaSessionDispositionPerformer: AnyObject {
    /// The page's session is over for good.
    func retireSession(_ report: BrowserMediaSessionReport)
    /// The page has no session now, though it may publish one again.
    func clearSession(_ report: BrowserMediaSessionReport)
    /// The page's session stands as it reports it.
    func publishSession(_ report: BrowserMediaSessionReport)
}
