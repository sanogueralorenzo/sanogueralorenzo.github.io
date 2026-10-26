import Foundation

/// Something a sidebar card offers. Each action carries how the widget that
/// offers it performs it: the software update card through its updater, the
/// Now Playing card through the media session store. An action a widget does
/// not offer does nothing there.
struct BrowserSidebarWidgetAction: Hashable, Sendable {
    // MARK: - Static Variables

    static let activateOwner = Self(name: "activateOwner")
    static let play = mediaSession(.play)
    static let pause = mediaSession(.pause)
    static let previousTrack = mediaSession(.previousTrack)
    static let nextTrack = mediaSession(.nextTrack)
    /// Widget-level only: muting is an element property, not a Media Session
    /// action a page can register a handler for.
    static let toggleMute = Self(name: "toggleMute") { store, session in
        store.toggleMute(of: session)
    }
    /// Hides this session's card until its tab plays again. Widget-level only.
    static let dismissMediaSession = Self(name: "dismissMediaSession") { store, session in
        store.dismissCard(of: session)
    }
    static let installUpdate = Self(name: "installUpdate") { $0.installUpdate() }
    /// The card opens the release's page itself.
    static let viewUpdateInformation = Self(name: "viewUpdateInformation")
    static let dismissExactUpdate = Self(name: "dismissExactUpdate") { updater in
        // Sparkle persists `.skip` against the exact appcast build. Its own
        // app-scoped store is authoritative, and a newer build is therefore
        // offered again without Crest maintaining a competing dismissal key.
        updater.skipUpdate()
    }
    static let cancelUpdate = Self(name: "cancelUpdate") { $0.cancelCurrentOperation() }
    static let installAndRelaunch = Self(name: "installAndRelaunch") { $0.installAndRelaunchNow() }
    static let retryUpdateInstallation = Self(name: "retryUpdateInstallation") {
        $0.retryApplicationTermination()
    }
    static let declineAutomaticUpdateChecks = Self(name: "declineAutomaticUpdateChecks") {
        $0.chooseAutomaticChecks(false)
    }
    static let enableAutomaticUpdateChecks = Self(name: "enableAutomaticUpdateChecks") {
        $0.chooseAutomaticChecks(true)
    }
    static let acknowledgeUpdateStatus = Self(name: "acknowledgeUpdateStatus") { $0.acknowledge() }
    /// Hides the update card until the person checks for updates or Crest
    /// restarts. Widget-level only: the update itself carries on.
    static let hideSoftwareUpdate = Self(name: "hideSoftwareUpdate") { $0.hide() }

    // MARK: - Variables

    let name: String
    private let softwareUpdatePerformance: (@MainActor @Sendable (any BrowserSoftwareUpdateActionPerformer) -> Void)?
    private let nowPlayingPerformance:
        (@MainActor @Sendable (any BrowserNowPlayingActionPerformer, BrowserMediaSessionSnapshot) -> Void)?

    // MARK: - Initializers

    private init(name: String) {
        self.name = name
        softwareUpdatePerformance = nil
        nowPlayingPerformance = nil
    }

    private init(
        name: String,
        softwareUpdate: @escaping @MainActor @Sendable (any BrowserSoftwareUpdateActionPerformer) -> Void
    ) {
        self.name = name
        softwareUpdatePerformance = softwareUpdate
        nowPlayingPerformance = nil
    }

    private init(
        name: String,
        nowPlaying:
            @escaping @MainActor @Sendable (any BrowserNowPlayingActionPerformer, BrowserMediaSessionSnapshot)
            -> Void
    ) {
        self.name = name
        softwareUpdatePerformance = nil
        nowPlayingPerformance = nowPlaying
    }

    // MARK: - Actions - Media sessions

    /// The card action that asks the page for one of its own Media Session
    /// actions.
    static func mediaSession(_ action: MediaSessionAction) -> Self {
        Self(name: "mediaSession.\(action)") { store, session in
            store.perform(action, on: session)
        }
    }

    // MARK: - Actions - Performing

    /// Performs the action on the software update card's updater.
    @MainActor
    func perform(on updater: any BrowserSoftwareUpdateActionPerformer) {
        softwareUpdatePerformance?(updater)
    }

    /// Performs the action on a Now Playing card's session.
    @MainActor
    func perform(on store: any BrowserNowPlayingActionPerformer, session: BrowserMediaSessionSnapshot) {
        nowPlayingPerformance?(store, session)
    }

    // MARK: - Actions - Identity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
