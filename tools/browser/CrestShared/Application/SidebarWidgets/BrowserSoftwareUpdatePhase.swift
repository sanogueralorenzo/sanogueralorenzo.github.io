import Foundation

/// Where a software update stands, from asking to check through to the
/// installed build, with how the update window and the sidebar card say so
/// and what each offers the person.
struct BrowserSoftwareUpdatePhase: Hashable, Identifiable, Sendable {
    // MARK: - Types

    /// The color a phase's symbol takes, which the view that draws it names.
    enum Tones: Sendable {
        case accent
        case success
        case warning
    }

    /// A button in the update window, with the card action it performs.
    struct WindowButton: Sendable {
        let title: LocalizedStringResource
        let action: BrowserSidebarWidgetAction
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

    /// What a phase offers on the sidebar card for an update in it.
    typealias CardOffer = @Sendable (BrowserSoftwareUpdateWidgetSnapshot) -> Set<BrowserSidebarWidgetAction>

    /// The update window's buttons for an update in a phase, or nil where the
    /// window shows none at all.
    typealias WindowOffer = @Sendable (BrowserSoftwareUpdateWidgetSnapshot) -> WindowButtons?

    // MARK: - Static Variables

    private static let waitingSymbol = "arrow.trianglehead.2.clockwise.rotate.90"
    private static let installSymbol = "arrow.trianglehead.2.clockwise.rotate.90.circle.fill"
    private static let settledSymbol = "checkmark.circle.fill"

    /// While the updater works, the card and the window offer to cancel.
    private static let cancellableCardActions: CardOffer = { snapshot in
        snapshot.allowsCancellation ? [.cancelUpdate] : []
    }
    private static let cancellableWindowButtons: WindowOffer = { _ in
        WindowButtons(trailing: [WindowButton(title: "Cancel", action: .cancelUpdate)])
    }

    /// A settled outcome waits for the person to dismiss it.
    private static let settledCardActions: CardOffer = { _ in
        [.acknowledgeUpdateStatus]
    }
    private static let settledWindowButtons: WindowOffer = { _ in
        WindowButtons(trailing: [WindowButton(title: "Dismiss", action: .acknowledgeUpdateStatus, confirms: true)])
    }

    /// Nothing is under way, so there is nothing to show.
    static let idle = BrowserSoftwareUpdatePhase(
        name: "idle", title: "Software Update", statusLabel: "Software Update")
    static let permission = BrowserSoftwareUpdatePhase(
        name: "permission", title: "Keep Crest Up to Date", statusLabel: "Permission required",
        cardActions: { _ in [.declineAutomaticUpdateChecks, .enableAutomaticUpdateChecks] },
        windowButtons: { _ in
            WindowButtons(
                leading: [WindowButton(title: "Not Now", action: .declineAutomaticUpdateChecks)],
                trailing: [
                    WindowButton(title: "Check Automatically", action: .enableAutomaticUpdateChecks, isProminent: true)
                ])
        })
    static let checking = BrowserSoftwareUpdatePhase(
        name: "checking", title: "Checking for Updates", statusLabel: "Checking",
        showsMessage: false, isWorking: true, windowShowsActivity: true, isHideable: true,
        cardActions: cancellableCardActions, windowButtons: cancellableWindowButtons)
    static let available = BrowserSoftwareUpdatePhase(
        name: "available", title: "Update Available", statusLabel: "Ready to download",
        informationOnlyStatusLabel: "Website release", isTitledByUpdate: true, isHideable: true,
        cardActions: { snapshot in
            var actions: Set<BrowserSidebarWidgetAction> = []
            if snapshot.allowsSkipping { actions.insert(.dismissExactUpdate) }
            if snapshot.allowsInstallation { actions.insert(.installUpdate) }
            if snapshot.isInformationOnly, snapshot.informationURL != nil {
                actions.insert(.viewUpdateInformation)
            }
            return actions
        },
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
        symbol: "arrow.down.circle.fill", showsMessage: false, isTransferring: true, isWorking: true,
        isHideable: true, cardActions: cancellableCardActions, windowButtons: cancellableWindowButtons)
    static let extracting = BrowserSoftwareUpdatePhase(
        name: "extracting", title: "Preparing Update", statusLabel: "Preparing",
        showsMessage: false, isTransferring: true, isWorking: true, windowShowsActivity: true, isHideable: true)
    static let readyToInstall = BrowserSoftwareUpdatePhase(
        name: "readyToInstall", title: "Ready to Install", statusLabel: "Ready to install",
        symbol: installSymbol, isHideable: true,
        cardActions: { snapshot in
            var actions: Set<BrowserSidebarWidgetAction> = []
            if snapshot.allowsInstallAndRelaunch {
                actions.insert(.installAndRelaunch)
            }
            if snapshot.allowsSkipping { actions.insert(.dismissExactUpdate) }
            return actions
        },
        windowButtons: { _ in
            WindowButtons(
                trailing: [WindowButton(title: "Install and Relaunch", action: .installAndRelaunch, isProminent: true)])
        })
    static let installing = BrowserSoftwareUpdatePhase(
        name: "installing", title: "Installing Update", statusLabel: "Installing",
        symbol: installSymbol, isWorking: true, windowShowsActivity: true, isHideable: true,
        cardActions: { snapshot in
            snapshot.allowsInstallationRetry ? [.retryUpdateInstallation] : []
        },
        windowButtons: { snapshot in
            guard snapshot.allowsInstallationRetry else { return WindowButtons() }
            return WindowButtons(
                trailing: [WindowButton(title: "Try Quitting Again", action: .retryUpdateInstallation)])
        })
    static let upToDate = BrowserSoftwareUpdatePhase(
        name: "upToDate", title: "Crest Is Up to Date", statusLabel: "Up to date",
        symbol: settledSymbol, tone: .success, cardActions: settledCardActions, windowButtons: settledWindowButtons)
    static let failed = BrowserSoftwareUpdatePhase(
        name: "failed", title: "Update Check Failed", statusLabel: "Update error",
        symbol: "exclamationmark.triangle.fill", tone: .warning, cardActions: settledCardActions,
        windowButtons: settledWindowButtons)
    static let installed = BrowserSoftwareUpdatePhase(
        name: "installed", title: "Update Installed", statusLabel: "Installed",
        symbol: settledSymbol, tone: .success, cardActions: settledCardActions, windowButtons: settledWindowButtons)
    /// Updates can't run in this build at all.
    static let unavailable = BrowserSoftwareUpdatePhase(
        name: "unavailable", title: "Software Update Unavailable", statusLabel: "Unavailable")

    /// Every phase, in the order an update moves through them.
    static let all: [BrowserSoftwareUpdatePhase] = [
        idle, permission, checking, available, downloading, extracting, readyToInstall, installing, upToDate, failed,
        installed, unavailable,
    ]

    // MARK: - Variables

    let name: String
    let title: LocalizedStringResource

    /// Whether the update's own title, when it has one, stands in for the
    /// phase's.
    let isTitledByUpdate: Bool

    /// The phase in a word or two, beside the card's progress.
    let statusLabel: LocalizedStringResource

    /// The status of a release offered only on the website, where it differs.
    let informationOnlyStatusLabel: LocalizedStringResource?

    let symbol: String
    let tone: Tones

    /// Whether the card shows the update's message under the phase. A phase
    /// whose progress says enough leaves it out.
    let showsMessage: Bool

    /// Whether bytes are moving, so a measured progress has something to
    /// measure.
    let isTransferring: Bool

    /// Whether the card shows that work is under way.
    let isWorking: Bool

    /// Whether the update window shows work under way while it has no
    /// measured progress.
    let windowShowsActivity: Bool

    /// Whether the person can hide the sidebar card while the update is in
    /// this phase: one that waits on nothing they must answer and has no
    /// Dismiss of its own.
    let isHideable: Bool

    /// The card's actions for an update in this phase, before hiding.
    private let offeredCardActions: CardOffer

    /// The update window's buttons for an update in this phase, or nil where
    /// the window shows none at all.
    private let offeredWindowButtons: WindowOffer

    var id: String { name }

    // MARK: - Initializers

    private init(
        name: String, title: LocalizedStringResource, statusLabel: LocalizedStringResource,
        informationOnlyStatusLabel: LocalizedStringResource? = nil, isTitledByUpdate: Bool = false,
        symbol: String = BrowserSoftwareUpdatePhase.waitingSymbol, tone: Tones = .accent, showsMessage: Bool = true,
        isTransferring: Bool = false, isWorking: Bool = false, windowShowsActivity: Bool = false,
        isHideable: Bool = false,
        cardActions: @escaping CardOffer = { _ in [] },
        windowButtons: @escaping WindowOffer = { _ in nil }
    ) {
        self.name = name
        self.title = title
        self.isTitledByUpdate = isTitledByUpdate
        self.statusLabel = statusLabel
        self.informationOnlyStatusLabel = informationOnlyStatusLabel
        self.symbol = symbol
        self.tone = tone
        self.showsMessage = showsMessage
        self.isTransferring = isTransferring
        self.isWorking = isWorking
        self.windowShowsActivity = windowShowsActivity
        self.isHideable = isHideable
        offeredCardActions = cardActions
        offeredWindowButtons = windowButtons
    }

    // MARK: - Actions - Offers

    /// What the sidebar card offers for `snapshot`, an update in this phase.
    func cardActions(for snapshot: BrowserSoftwareUpdateWidgetSnapshot) -> Set<BrowserSidebarWidgetAction> {
        var actions = offeredCardActions(snapshot)
        if isHideable { actions.insert(.hideSoftwareUpdate) }
        return actions
    }

    /// The update window's buttons for `snapshot`, an update in this phase,
    /// or nil where the window shows none at all.
    func windowButtons(for snapshot: BrowserSoftwareUpdateWidgetSnapshot) -> WindowButtons? {
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
