import Foundation

/// A check for updates Crest asks Sparkle to run, now or once its current
/// session ends, and how the updater starts it.
struct BrowserSoftwareUpdateCheck: Equatable, Sendable {
    // MARK: - Static Variables

    /// A check the person asked for, which Sparkle shows as it runs.
    static let userInitiated = Self(name: "userInitiated", rank: 1, isUserInitiated: true) {
        $0.checkForUpdates()
    }
    /// A check Crest runs on its own, which Sparkle keeps quiet unless it
    /// finds an update.
    static let background = Self(name: "background", rank: 0) {
        $0.checkForUpdatesInBackground()
    }
    /// A check that downloads the newest update it finds, so the person
    /// installs the latest build rather than the one first offered.
    static let downloadLatest = Self(name: "downloadLatest", rank: 2, downloadsOffer: true) {
        $0.checkForUpdates()
    }

    // MARK: - Variables

    let name: String

    /// Which pending check a later request replaces: a check replaces one
    /// that ranks below it.
    let rank: Int

    /// Whether the person asked for the check, so a session already in
    /// progress still hears of it.
    let isUserInitiated: Bool

    /// Whether the update the check finds downloads at once.
    let downloadsOffer: Bool

    private let begin: @MainActor @Sendable (any BrowserSoftwareUpdateChecking) -> Void

    // MARK: - Initializers

    private init(
        name: String, rank: Int, isUserInitiated: Bool = false, downloadsOffer: Bool = false,
        begin: @escaping @MainActor @Sendable (any BrowserSoftwareUpdateChecking) -> Void
    ) {
        self.name = name
        self.rank = rank
        self.isUserInitiated = isUserInitiated
        self.downloadsOffer = downloadsOffer
        self.begin = begin
    }

    // MARK: - Actions - Checking

    /// Whether a request for this check replaces `pending`, which waits for
    /// the updater's session to end.
    func replaces(_ pending: Self) -> Bool {
        rank >= pending.rank
    }

    /// Starts the check on `updater`.
    @MainActor
    func start(on updater: any BrowserSoftwareUpdateChecking) {
        begin(updater)
    }

    // MARK: - Actions - Identity

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.name == rhs.name
    }
}
