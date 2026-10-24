import Foundation
import Observation

@MainActor
@Observable
final class BrowserSoftwareUpdateModel {
    // MARK: - Static Variables

    private static let readyMessage = "The update is ready. Crest will relaunch to finish installing it."
    private static let automaticReadyMessage =
        "The update is ready. Restart Crest now, or quit normally to install it the next time Crest opens."
    private static let waitingToQuitMessage = "Waiting for Crest to quit before installing…"

    // MARK: - Variables

    private(set) var phase = BrowserSoftwareUpdatePhase.idle
    private(set) var updateTitle: String?
    private(set) var updateVersion: String?
    private(set) var updateBuild: String?
    private(set) var releaseNotes: String?
    private(set) var informationURL: URL?
    private(set) var message: String?
    private(set) var progress: Double?
    private(set) var isInformationOnly = false
    private(set) var isAutomaticUpdate = false
    private(set) var didRelaunch = false
    private(set) var canRetryTermination = false
    private(set) var isFixture = false
    private(set) var allowsOfferRefresh = true
    /// The person hid the sidebar card, which stays hidden until they check
    /// for updates or Crest restarts. Sparkle's pending choice is untouched,
    /// and Settings still shows where the update stands.
    private(set) var isHidden = false

    @ObservationIgnored var refreshBeforeDownload: (() -> Void)?

    @ObservationIgnored private weak var widgetSource: BrowserSoftwareUpdateWidgetSource?

    @ObservationIgnored private var expectedDownloadLength: UInt64?
    @ObservationIgnored private var receivedDownloadLength: UInt64 = 0
    @ObservationIgnored private var permissionResponse: ((Bool) -> Void)?
    @ObservationIgnored private var cancellation: (() -> Void)?
    @ObservationIgnored private var install: (() -> Void)?
    @ObservationIgnored private var skip: (() -> Void)?
    @ObservationIgnored private var dismiss: (() -> Void)?
    @ObservationIgnored private var installAndRelaunch: (() -> Void)?
    /// Whether `installAndRelaunch` may run again to ask Crest to quit once
    /// more. Sparkle's install reply runs once; its retry, and the immediate
    /// install of an update downloaded automatically, ask for the quit again
    /// each time they run.
    @ObservationIgnored private var relaunchRepeats = false
    @ObservationIgnored private var retryTermination: (() -> Void)?
    @ObservationIgnored private var acknowledgement: (() -> Void)?

    var sidebarWidgetSnapshot: BrowserSoftwareUpdateWidgetSnapshot? {
        guard phase != .idle, !isHidden else { return nil }
        return snapshot
    }

    /// Where the update stands now, whether or not the sidebar shows it.
    var snapshot: BrowserSoftwareUpdateWidgetSnapshot {
        BrowserSoftwareUpdateWidgetSnapshot(
            phase: phase,
            title: updateTitle ?? "Crest Update",
            version: updateVersion,
            build: updateBuild,
            releaseNotes: releaseNotes,
            informationURL: informationURL,
            message: message,
            progress: progress,
            isInformationOnly: isInformationOnly,
            allowsInstallation: install != nil && !isInformationOnly,
            allowsSkipping: skip != nil,
            allowsCancellation: cancellation != nil,
            allowsInstallAndRelaunch: installAndRelaunch != nil,
            allowsInstallationRetry: canRetryTermination,
            isFixture: isFixture
        )
    }

    // MARK: - Initializers

    init(widgetSource: BrowserSoftwareUpdateWidgetSource? = nil) {
        self.widgetSource = widgetSource
        widgetSource?.bind(self)
    }

    // MARK: - Actions - Permission

    func presentPermissionRequest(response: @escaping (Bool) -> Void) {
        resetCallbacks()
        phase = .permission
        message = "Crest can check for updates automatically without sending a system profile."
        permissionResponse = response
        present()
    }

    func chooseAutomaticChecks(_ isEnabled: Bool) {
        let response = permissionResponse
        permissionResponse = nil
        response?(isEnabled)
        reset()
    }

    // MARK: - Actions - Checking

    func presentChecking(cancellation: @escaping () -> Void) {
        resetCallbacks()
        phase = .checking
        message = "Checking for a newer version of Crest…"
        self.cancellation = cancellation
        present()
    }

    func presentNoUpdate(
        message: String,
        acknowledgement: @escaping () -> Void
    ) {
        resetCallbacks()
        phase = .upToDate
        self.message = message
        self.acknowledgement = acknowledgement
        present()
    }

    func presentError(
        message: String,
        acknowledgement: @escaping () -> Void
    ) {
        resetCallbacks()
        phase = .failed
        self.message = message
        self.acknowledgement = acknowledgement
        present()
    }

    /// Ends only an undownloaded available-update choice so Sparkle can run a
    /// fresh feed check. This is intentionally distinct from `.skip`, which
    /// persists a version exclusion, and is unavailable once download or
    /// installation work has begun.
    @discardableResult
    func beginRefreshingAvailableUpdate(cancellation: (() -> Void)? = nil) -> Bool {
        guard phase == .available, allowsOfferRefresh, let dismiss else { return false }
        resetCallbacks()
        self.cancellation = cancellation
        phase = .checking
        message = "Checking whether a newer Crest update is available…"
        present()
        dismiss()
        return true
    }

    func finishRefreshIfNeeded() {
        guard phase == .checking else { return }
        reset()
    }

    func cancelCurrentOperation() {
        let cancellation = self.cancellation
        self.cancellation = nil
        cancellation?()
        reset()
    }

    func acknowledge() {
        let acknowledgement = self.acknowledgement
        self.acknowledgement = nil
        acknowledgement?()
        reset()
    }

    // MARK: - Actions - Offers

    func presentUpdate(
        title: String,
        version: String?,
        build: String? = nil,
        releaseNotes: String? = nil,
        informationURL: URL? = nil,
        isInformationOnly: Bool,
        isFixture: Bool = false,
        allowsOfferRefresh: Bool = true,
        install: @escaping () -> Void,
        skip: @escaping () -> Void,
        dismiss: @escaping () -> Void = {}
    ) {
        resetCallbacks()
        phase = .available
        updateTitle = title
        updateVersion = version
        updateBuild = build
        self.releaseNotes = releaseNotes
        self.informationURL = informationURL
        self.isInformationOnly = isInformationOnly
        self.isAutomaticUpdate = false
        self.isFixture = isFixture
        self.allowsOfferRefresh = allowsOfferRefresh
        self.install = install
        self.skip = skip
        self.dismiss = dismiss
        message =
            isInformationOnly
            ? "This release is available from the Crest website."
            : "A new version of Crest is ready to download."
        present()
    }

    func setReleaseNotes(_ releaseNotes: String) {
        self.releaseNotes = releaseNotes
        publishWidgetState()
    }

    func presentReleaseNotesFailure(_ description: String) {
        guard releaseNotes == nil else { return }
        releaseNotes = description
        publishWidgetState()
    }

    func installUpdate() {
        guard phase == .available, !isInformationOnly, install != nil else { return }
        if allowsOfferRefresh, !isFixture, let refreshBeforeDownload {
            refreshBeforeDownload()
            return
        }
        installPresentedUpdate()
    }

    func installPresentedUpdate() {
        guard !isInformationOnly, let install else { return }
        self.install = nil
        skip = nil
        phase = .downloading
        publishWidgetState()
        install()
    }

    func skipUpdate() {
        let skip = self.skip
        self.skip = nil
        install = nil
        installAndRelaunch = nil
        skip?()
        reset()
    }

    // MARK: - Actions - Downloads

    /// Starts tracking Sparkle's silent automatic-download path. A manual
    /// download reaches the updater delegate first too, so preserve the
    /// cancellable user-driver session when it already owns this build.
    @discardableResult
    func presentAutomaticDownload(
        title: String,
        version: String?,
        build: String,
        releaseNotes: String?,
        informationURL: URL?,
        isFixture: Bool = false
    ) -> Bool {
        guard
            !(phase == .downloading
                && updateBuild == build
                && !isAutomaticUpdate)
        else { return false }

        resetCallbacks()
        phase = .downloading
        updateTitle = title
        updateVersion = version
        updateBuild = build
        self.releaseNotes = releaseNotes
        self.informationURL = informationURL
        message = "Downloading the update automatically…"
        progress = nil
        isInformationOnly = false
        isAutomaticUpdate = true
        self.isFixture = isFixture
        expectedDownloadLength = nil
        receivedDownloadLength = 0
        present()
        return true
    }

    func presentAutomaticUpdateFailure(
        title: String,
        version: String?,
        build: String,
        message: String
    ) {
        resetCallbacks()
        phase = .failed
        updateTitle = title
        updateVersion = version
        updateBuild = build
        self.message = message
        progress = nil
        isInformationOnly = false
        isAutomaticUpdate = true
        acknowledgement = { [weak self] in self?.reset() }
        present()
    }

    func presentDownload(cancellation: @escaping () -> Void) {
        phase = .downloading
        message = "Downloading the update…"
        progress = nil
        expectedDownloadLength = nil
        receivedDownloadLength = 0
        self.cancellation = cancellation
        present()
    }

    func setExpectedDownloadLength(_ length: UInt64) {
        expectedDownloadLength = length > 0 ? length : nil
        updateDownloadProgress()
        publishWidgetState()
    }

    func receiveDownloadedBytes(_ length: UInt64) {
        let addition = receivedDownloadLength.addingReportingOverflow(length)
        receivedDownloadLength = addition.overflow ? .max : addition.partialValue
        updateDownloadProgress()
        publishWidgetState()
    }

    func presentExtraction() {
        phase = .extracting
        message = "Preparing the update…"
        progress = nil
        cancellation = nil
        present()
    }

    func setExtractionProgress(_ progress: Double) {
        self.progress = min(max(progress, 0), 1)
        publishWidgetState()
    }

    private func updateDownloadProgress() {
        guard let expectedDownloadLength else {
            progress = nil
            return
        }
        progress = min(
            Double(receivedDownloadLength) / Double(expectedDownloadLength),
            1
        )
    }

    // MARK: - Actions - Installing

    /// An update Sparkle downloaded on its own. Restarting runs Sparkle's
    /// immediate install, which asks Crest to quit each time it runs.
    func presentAutomaticUpdateReady(
        title: String,
        version: String?,
        build: String,
        releaseNotes: String?,
        informationURL: URL?,
        isFixture: Bool = false,
        installAndRelaunch: @escaping () -> Void
    ) {
        resetCallbacks()
        phase = .readyToInstall
        updateTitle = title
        updateVersion = version
        updateBuild = build
        self.releaseNotes = releaseNotes
        self.informationURL = informationURL
        message = Self.automaticReadyMessage
        progress = nil
        isInformationOnly = false
        isAutomaticUpdate = true
        self.isFixture = isFixture
        self.installAndRelaunch = installAndRelaunch
        relaunchRepeats = true
        present()
    }

    func presentReadyToInstall(
        install: @escaping () -> Void,
        cancel: @escaping () -> Void
    ) {
        phase = .readyToInstall
        message = Self.readyMessage
        installAndRelaunch = install
        relaunchRepeats = false
        skip = cancel
        present()
    }

    func presentInstalling(
        applicationTerminated: Bool,
        retryTermination: @escaping () -> Void
    ) {
        phase = .installing
        message =
            applicationTerminated
            ? "Installing the update…"
            : Self.waitingToQuitMessage
        self.retryTermination = applicationTerminated ? nil : retryTermination
        canRetryTermination = !applicationTerminated
        present()
    }

    func presentInstalled(
        relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        resetCallbacks()
        phase = .installed
        didRelaunch = relaunched
        message =
            relaunched
            ? "Crest was updated and relaunched successfully."
            : "Crest was updated successfully."
        self.acknowledgement = acknowledgement
        present()
    }

    /// Asks Crest to quit so the update installs and Crest opens again. Until
    /// it quits, the same request can be made again.
    func installAndRelaunchNow() {
        let reply = installAndRelaunch
        installAndRelaunch = nil
        skip = nil
        dismiss = nil
        phase = .installing
        message = Self.waitingToQuitMessage
        if relaunchRepeats {
            retryTermination = reply
            canRetryTermination = reply != nil
        }
        publishWidgetState()
        reply?()
    }

    func retryApplicationTermination() {
        retryTermination?()
    }

    /// Crest was asked to quit and stayed open: a page asked to stay, the
    /// person kept their downloads, or a Space is still being deleted. An
    /// update waiting on that quit is ready again, and restarting asks Crest
    /// to quit once more; quitting normally still installs it.
    func applicationStayedOpen() {
        guard phase == .installing, let retryTermination else { return }
        phase = .readyToInstall
        message = isAutomaticUpdate ? Self.automaticReadyMessage : Self.readyMessage
        installAndRelaunch = retryTermination
        relaunchRepeats = true
        self.retryTermination = nil
        canRetryTermination = false
        present()
    }

    func dismissInstallation() {
        reset()
    }

    // MARK: - Actions - Visibility

    /// Hides the sidebar card until the person checks for updates or Crest
    /// restarts. Sparkle is not told, so the update carries on as it was.
    func hide() {
        guard !isHidden else { return }
        isHidden = true
        publishWidgetState()
    }

    /// Shows the sidebar card again once the person checks for updates.
    func reveal() {
        guard isHidden else { return }
        isHidden = false
        publishWidgetState()
    }

    // MARK: - Actions - Presentation

    private func present() {
        publishWidgetState()
    }

    private func reset() {
        resetCallbacks()
        phase = .idle
        updateTitle = nil
        updateVersion = nil
        updateBuild = nil
        releaseNotes = nil
        informationURL = nil
        message = nil
        progress = nil
        isInformationOnly = false
        isAutomaticUpdate = false
        isFixture = false
        didRelaunch = false
        canRetryTermination = false
        expectedDownloadLength = nil
        receivedDownloadLength = 0
        publishWidgetState()
    }

    private func resetCallbacks() {
        permissionResponse = nil
        cancellation = nil
        install = nil
        skip = nil
        dismiss = nil
        installAndRelaunch = nil
        relaunchRepeats = false
        retryTermination = nil
        canRetryTermination = false
        acknowledgement = nil
    }

    private func publishWidgetState() {
        widgetSource?.publish(sidebarWidgetSnapshot)
    }
}

extension BrowserSoftwareUpdateModel: BrowserSoftwareUpdateActionPerformer {}
