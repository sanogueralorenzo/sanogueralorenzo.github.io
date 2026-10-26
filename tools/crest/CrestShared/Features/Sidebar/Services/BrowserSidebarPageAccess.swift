import Foundation

/// Everything the sidebar needs from the page layer, and nothing else.
///
/// The two shells keep their own page stores — one pools windowed cards, the
/// other owns a single compact stack — but the sidebar only ever asks the same
/// handful of questions and issues the same handful of commands. Those live
/// here as closures, which one initializer binds over either store as a
/// `BrowserPageOwner`; the Mac adds a tab's sharing and the audio a row draws.
///
/// Every closure reads through its store at call time rather than capturing a
/// snapshot, so Observation still tracks what a row touched — `residencyRevision`
/// in particular exists to be read inside a view body.
@MainActor
struct BrowserSidebarPageAccess {
    /// Whether a tab is holding a resident page, wherever it lives.
    let containsResidentPage: @MainActor (UUID) -> Bool

    /// Whether the resident page a tab holds is the one this Space and profile
    /// own. A stale row asking about a tab that moved gets `false`.
    let containsResidentPageMatching: @MainActor (BrowserTabRuntimeAssignment) -> Bool

    /// The accent a site's own theme color contributes to its favicon.
    let siteThemeIconAccent: @MainActor (BrowserTabRuntimeAssignment) -> BrowserTabIconAccent?

    /// Bumped by the store whenever residency changes. Read it to make a view
    /// depend on residency, which is otherwise invisible to Observation.
    let residencyRevision: @MainActor () -> Int

    /// Brings the session's current selection on screen.
    let selectPages: @MainActor () -> Void

    let deactivatePagePresentation: @MainActor () -> Void

    /// Shared across both shells already, so the sidebar holds the real thing
    /// rather than a closure over it.
    let downloadCenter: BrowserDownloadCenter

    /// Whether another page shares the page a tab holds, if the Space and
    /// profile still own it. A shell whose pages cannot be shared answers no.
    var isSharedAsTab: @MainActor (BrowserTabRuntimeAssignment) -> Bool = { _ in false }

    /// Whether the page a tab holds shares another tab, if the Space and
    /// profile still own it.
    var isSharingTab: @MainActor (BrowserTabRuntimeAssignment) -> Bool = { _ in false }

    /// Stops every tab sharing the page a tab holds takes part in.
    var stopTabSharing: @MainActor (BrowserTabRuntimeAssignment) -> Void = { _ in }

    /// The tab at the other end of the tab sharing the page a tab holds takes
    /// part in: the tab sharing it, or the tab it shares. Nil when Crest does
    /// not know it.
    var tabSharingCounterpartID: @MainActor (BrowserTabRuntimeAssignment) -> UUID? = { _ in nil }

    /// The media session a tab's page publishes, or nil while it publishes
    /// none, as in a shell that reports no media sessions.
    var mediaSession: @MainActor (BrowserTabRuntimeAssignment) -> BrowserMediaSessionSnapshot? = { _ in nil }

    /// Mutes or unmutes the sound a tab's page plays.
    var setMuted: @MainActor (Bool, BrowserTabRuntimeAssignment) -> Void = { _, _ in }

    /// The engine's measure of the sound a tab's page plays, band by band, or
    /// nil where its engine does not measure it.
    var audioSpectrum: @MainActor (BrowserTabRuntimeAssignment) -> BrowserAudioSpectrumFeed? = { _ in nil }
    /// The page's current navigation state, read from the owning window so a
    /// row observes URL changes before navigation finishes. Nil when unloaded.
    var liveState: @MainActor (BrowserTabRuntimeAssignment) -> PageLiveState? = { _ in nil }

}

extension BrowserSidebarPageAccess {
    /// Binds the sidebar's page seam to a window's page owner, which
    /// `selectPages` brings forward; by default the owner shows its selected
    /// tab.
    ///
    /// The owner is captured rather than read once: every closure goes back to
    /// it at call time, which is what keeps a row's residency and favicon
    /// reads inside Observation's tracking.
    init(
        pages: some BrowserPageOwner, browser: BrowserStore,
        selectPages: (@MainActor () -> Void)? = nil
    ) {
        self.init(
            containsResidentPage: { tabID in
                pages.containsResidentPage(for: tabID) || pages.nativeTabs.tabIDs.contains(tabID)
            },
            containsResidentPageMatching: { assignment in
                pages.containsResidentPage(matching: assignment) || pages.nativeTabs.contains(assignment)
            },
            siteThemeIconAccent: { assignment in
                pages.siteThemeIconAccent(matching: assignment)
            },
            residencyRevision: { pages.residencyRevision &+ pages.nativeTabs.residencyRevision },
            selectPages: selectPages ?? { pages.select(at: .now) },
            deactivatePagePresentation: { pages.deactivatePagePresentation() },
            downloadCenter: pages.downloadCenter,
            mediaSession: { assignment in
                pages.mediaSession(matching: assignment)
            },
            setMuted: { muted, assignment in
                pages.setMuted(muted, matching: assignment)
            },
            liveState: { assignment in
                pages.host.page(matching: assignment)?.live
            }
        )
    }
}
