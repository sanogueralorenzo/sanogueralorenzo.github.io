import Foundation

/// One tab's page as its status marks read it and act on it, for a row or a
/// tile drawn for one Space. Everything here is live page presentation, read
/// through the page layer each time, so a mark follows the page as it changes.
@MainActor
struct BrowserTabStatusSource {
    // MARK: - Variables

    let tabID: UUID
    let context: BrowserSidebarListContext

    /// Whether the row or tile drawing the marks may act now, asked when one
    /// is used.
    let canAct: () -> Bool

    // MARK: - Actions - Reading

    /// The media session the tab's page publishes, whether or not its Now
    /// Playing card is hidden.
    var mediaSession: BrowserMediaSessionSnapshot? { context.mediaSession(of: tabID) }

    #if os(macOS)
        /// The agent using the tab now, when one does.
        var agentSession: AgentSessionState? {
            context.browser.core.state.agentSessions.first { $0.tabIDs.contains(tabID) }
        }
    #endif

    /// Whether another page shares the tab's page.
    var isShared: Bool { context.isSharedAsTab(tabID) }

    /// Whether the tab's page shares another tab.
    var isSharing: Bool { context.isSharingTab(tabID) }

    /// The tab at the other end of the tab sharing the tab's page takes part
    /// in, when Crest knows it and the Space holds it.
    var sharingCounterpart: TabStateModel? { context.tabSharingCounterpart(of: tabID) }

    /// The engine's measure of the sound the tab's page plays, where its
    /// engine measures it.
    var audioSpectrum: BrowserAudioSpectrumFeed? { context.audioSpectrum(of: tabID) }

    /// The color the tab's page declares for itself, when it declares one.
    var siteTheme: BrowserTabIconAccent? { context.siteThemeAccent(of: tabID) }

    /// The icon the tab wears, whose colors stand in for a page that declares
    /// none.
    var favicon: FaviconAssets.Image? { context.favicons.icon(of: tabID) }

    // MARK: - Actions - Page

    /// Mutes or unmutes the sound the tab's page plays.
    func setMuted(_ muted: Bool) {
        context.setMuted(muted, of: tabID)
    }

    #if os(macOS)
        /// Stops every agent using the tab from using it.
        func stopAgent() {
            _ = try? context.browser.core.send(StopAgentTab(tabID: tabID))
        }

        /// Disconnects the agent using the tab.
        func disconnectAgent() {
            guard let session = agentSession else { return }
            _ = try? context.browser.core.send(EndAgentSession(sessionID: session.sessionID))
        }
    #endif

    /// Stops every tab sharing the tab's page takes part in.
    func stopSharing() {
        context.stopTabSharing(tabID)
    }

    /// Shows the tab at the other end of the tab sharing.
    func showSharingCounterpart() {
        guard let counterpart = sharingCounterpart else { return }
        context.select(counterpart.id)
    }
}
