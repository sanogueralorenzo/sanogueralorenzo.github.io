import Foundation

/// Where a software update stands, from checking through to the
/// installed build, with what the update screen offers the person.
struct BrowserSoftwareUpdatePhase: Hashable, Identifiable, Sendable {
    // MARK: - Types

    /// The color a phase's symbol takes, which the view that draws it names.
    enum Tones: Sendable {
        case accent
        case success
        case warning
    }

    /// A button in the update window, with the action it performs.
    struct WindowButton: Sendable {
        let title: LocalizedStringResource
        let action: BrowserSoftwareUpdateAction
        /// The page the button opens instead of performing its action.
        var destination: URL?
        var isProminent = false
        /// Whether Return presses the button, where the window lets it.
        var confirms = false
    }

    /// The update window's buttons, before and after the space between them.
    struct WindowButtons: Sendable {
        var leading: [WindowButton] = []
        var trailing: [WindowButton] = []
    }

    /// The update window's buttons for an update in a phase, or nil where the
    /// window shows none at all.
    typealias WindowOffer = @Sendable (BrowserSoftwareUpdateSnapshot) -> WindowButtons?

    // MARK: - Static Variables

    private static let waitingSymbol = "arrow.trianglehead.2.clockwise.rotate.90"
    private static let installSymbol = "arrow.trianglehead.2.clockwise.rotate.90.circle.fill"
    private static let settledSymbol = "checkmark.circle.fill"

    private static let cancellableWindowButtons: WindowOffer = { _ in
        WindowButtons(trailing: [WindowButton(title: "Cancel", action: .cancelUpdate)])
    }

    /// A settled outcome waits for the person to dismiss it.
    private static let settledWindowButtons: WindowOffer = { _ in
        WindowButtons(trailing: [WindowButton(title: "Dismiss", action: .acknowledgeUpdateStatus, confirms: true)])
    }

    /// Nothing is under way, so there is nothing to show.
    static let idle = BrowserSoftwareUpdatePhase(
        name: "idle", title: "Software Update", statusLabel: "Software Update")
    static let checking = BrowserSoftwareUpdatePhase(
        name: "checking", title: "Checking for Updates", statusLabel: "Checking",
        isWorking: true, windowShowsActivity: true,
        windowButtons: cancellableWindowButtons)
    static let available = BrowserSoftwareUpdatePhase(
        name: "available", title: "Update Available", statusLabel: "Ready to download",
        isTitledByUpdate: true,
        windowButtons: { snapshot in
            let skip = WindowButton(title: "Skip This Version", action: .dismissExactUpdate)
            if snapshot.isInformationOnly, let informationURL = snapshot.informationURL {
                return WindowButtons(
                    leading: [skip],
                    trailing: [
                        WindowButton(
                            title: "View Release", action: .viewUpdateInformation, destination: informationURL,
                            isProminent: true)
                    ])
            }
            return WindowButtons(
                leading: [skip],
                trailing: [WindowButton(title: "Download and Install", action: .installUpdate, isProminent: true)])
        })
    static let downloading = BrowserSoftwareUpdatePhase(
        name: "downloading", title: "Downloading Update", statusLabel: "Downloading",
        symbol: "arrow.down.circle.fill", isTransferring: true, isWorking: true,
        windowButtons: cancellableWindowButtons)
    static let extracting = BrowserSoftwareUpdatePhase(
        name: "extracting", title: "Preparing Update", statusLabel: "Preparing",
        isTransferring: true, isWorking: true, windowShowsActivity: true)
    static let readyToInstall = BrowserSoftwareUpdatePhase(
        name: "readyToInstall", title: "Ready to Install", statusLabel: "Ready to install",
        symbol: installSymbol,
        windowButtons: { _ in
            WindowButtons(
                trailing: [WindowButton(title: "Install and Relaunch", action: .installAndRelaunch, isProminent: true)])
        })
    static let installing = BrowserSoftwareUpdatePhase(
        name: "installing", title: "Installing Update", statusLabel: "Installing",
        symbol: installSymbol, isWorking: true, windowShowsActivity: true,
        windowButtons: { snapshot in
            guard snapshot.allowsInstallationRetry else { return WindowButtons() }
            return WindowButtons(
                trailing: [WindowButton(title: "Try Quitting Again", action: .retryUpdateInstallation)])
        })
    static let upToDate = BrowserSoftwareUpdatePhase(
        name: "upToDate", title: "Crest Is Up to Date", statusLabel: "Up to date",
        symbol: settledSymbol, tone: .success, windowButtons: settledWindowButtons)
    static let failed = BrowserSoftwareUpdatePhase(
        name: "failed", title: "Update Check Failed", statusLabel: "Update error",
        symbol: "exclamationmark.triangle.fill", tone: .warning, windowButtons: settledWindowButtons)
    static let installed = BrowserSoftwareUpdatePhase(
        name: "installed", title: "Update Installed", statusLabel: "Installed",
        symbol: settledSymbol, tone: .success, windowButtons: settledWindowButtons)
    /// Updates can't run in this build at all.
    static let unavailable = BrowserSoftwareUpdatePhase(
        name: "unavailable", title: "Software Update Unavailable", statusLabel: "Unavailable")

    /// Every phase, in the order an update moves through them.
    static let all: [BrowserSoftwareUpdatePhase] = [
        idle, checking, available, downloading, extracting, readyToInstall, installing, upToDate, failed,
        installed, unavailable,
    ]

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource

    /// Whether the update's own title, when it has one, stands in for the
    /// phase's.
    let isTitledByUpdate: Bool

    /// The phase in a word or two, beside its progress.
    let statusLabel: LocalizedStringResource

    let symbol: String
    let tone: Tones

    /// Whether bytes are moving, so a measured progress has something to
    /// measure.
    let isTransferring: Bool

    /// Whether the screen shows that work is under way.
    let isWorking: Bool

    /// Whether the update window shows work under way while it has no
    /// measured progress.
    let windowShowsActivity: Bool

    /// The update window's buttons for an update in this phase, or nil where
    /// the window shows none at all.
    private let offeredWindowButtons: WindowOffer

    var id: String { name }

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, statusLabel: LocalizedStringResource,
        isTitledByUpdate: Bool = false,
        symbol: String = BrowserSoftwareUpdatePhase.waitingSymbol, tone: Tones = .accent, showsMessage: Bool = true,
        isTransferring: Bool = false, isWorking: Bool = false, windowShowsActivity: Bool = false,
        windowButtons: @escaping WindowOffer = { _ in nil }
    ) {
        self.name = name
        self.title = title
        self.isTitledByUpdate = isTitledByUpdate
        self.statusLabel = statusLabel
        self.symbol = symbol
        self.tone = tone
        self.isTransferring = isTransferring
        self.isWorking = isWorking
        self.windowShowsActivity = windowShowsActivity
        offeredWindowButtons = windowButtons
    }

    // MARK: - Actions - Offers

    /// The update window's buttons for `snapshot`, an update in this phase,
    /// or nil where the window shows none at all.
    func windowButtons(for snapshot: BrowserSoftwareUpdateSnapshot) -> WindowButtons? {
        offeredWindowButtons(snapshot)
    }

    // MARK: - Actions - Identity

    static func == (lhs: BrowserSoftwareUpdatePhase, rhs: BrowserSoftwareUpdatePhase) -> Bool {
        lhs.name == rhs.name
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}
