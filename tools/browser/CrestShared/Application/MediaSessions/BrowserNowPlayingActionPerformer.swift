import Foundation

/// What a Now Playing card's actions ask of the store that keeps its session.
@MainActor
protocol BrowserNowPlayingActionPerformer: AnyObject {
    /// Hides the session's card until its tab plays again.
    func dismissCard(of session: BrowserMediaSessionSnapshot)
    /// Mutes the session's page media, or unmutes it.
    func toggleMute(of session: BrowserMediaSessionSnapshot)
    /// Asks the page for one of the Media Session actions it offers.
    func perform(_ action: MediaSessionAction, on session: BrowserMediaSessionSnapshot)
}
