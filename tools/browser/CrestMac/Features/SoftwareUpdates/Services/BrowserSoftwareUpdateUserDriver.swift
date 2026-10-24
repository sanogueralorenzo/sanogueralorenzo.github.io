import Foundation
import Sparkle

struct BrowserSoftwareUpdateMetadata: Equatable, Sendable {
    let title: String
    let version: String?
    let build: String
    let releaseNotes: String?
    let informationURL: URL?

    init(
        title: String,
        version: String?,
        build: String,
        releaseNotes: String?,
        informationURL: URL?
    ) {
        self.title = title
        self.version = version
        self.build = build
        self.releaseNotes = releaseNotes
        self.informationURL = informationURL
    }

    init(appcastItem: SUAppcastItem) {
        title =
            appcastItem.title
            ?? "Crest \(appcastItem.displayVersionString)"
        version = appcastItem.displayVersionString
        build = appcastItem.versionString
        releaseNotes = appcastItem.itemDescription
        informationURL = appcastItem.infoURL
    }
}

/// Adapts Sparkle's silent automatic-update delegate callbacks to the same
/// observable state used by Crest's manual user driver and sidebar widget.
@MainActor
final class BrowserAutomaticSoftwareUpdatePresenter {
    private let model: BrowserSoftwareUpdateModel
    private var activeUpdate: BrowserSoftwareUpdateMetadata?

    init(model: BrowserSoftwareUpdateModel) {
        self.model = model
    }

    func downloadDidBegin(_ update: BrowserSoftwareUpdateMetadata) {
        guard
            model.presentAutomaticDownload(
                title: update.title,
                version: update.version,
                build: update.build,
                releaseNotes: update.releaseNotes,
                informationURL: update.informationURL
            )
        else { return }
        activeUpdate = update
    }

    func extractionDidBegin(_ update: BrowserSoftwareUpdateMetadata) {
        if activeUpdate?.build != update.build {
            downloadDidBegin(update)
        }
        guard activeUpdate?.build == update.build else { return }
        model.presentExtraction()
    }

    func installationDidBecomeReady(
        _ update: BrowserSoftwareUpdateMetadata,
        installAndRelaunch: @escaping () -> Void
    ) {
        activeUpdate = update
        model.presentAutomaticUpdateReady(
            title: update.title,
            version: update.version,
            build: update.build,
            releaseNotes: update.releaseNotes,
            informationURL: update.informationURL,
            installAndRelaunch: installAndRelaunch
        )
    }

    func updateDidFail(_ error: any Error) {
        guard let activeUpdate else { return }
        self.activeUpdate = nil
        let error = error as NSError
        let message = [
            error.localizedDescription,
            error.localizedRecoverySuggestion,
        ]
        .compactMap { $0 }
        .joined(separator: " ")
        model.presentAutomaticUpdateFailure(
            title: activeUpdate.title,
            version: activeUpdate.version,
            build: activeUpdate.build,
            message: message
        )
    }
}

@MainActor
final class BrowserSoftwareUpdateUserDriver: NSObject, SPUUserDriver,
    SPUUpdaterDelegate
{
    /// The marketing version of the bundle this process started from.
    nonisolated static var bundleVersion: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString")
            as? String
    }

    let model: BrowserSoftwareUpdateModel
    var channel: BrowserSoftwareUpdateChannel
    var updateCycleDidFinish: (() -> Void)?
    var updateWasFound: (() -> Void)?
    private let feedURLOverride: URL?
    private let automaticUpdatePresenter: BrowserAutomaticSoftwareUpdatePresenter
    /// The running marketing version, kept so a cached update left behind by an
    /// older installed copy can be recognised and refused.
    private let runningVersion: String?

    init(
        model: BrowserSoftwareUpdateModel,
        channel: BrowserSoftwareUpdateChannel,
        feedURLOverride: URL? = nil,
        runningVersion: String? = BrowserSoftwareUpdateUserDriver.bundleVersion
    ) {
        self.model = model
        self.channel = channel
        self.feedURLOverride = feedURLOverride
        self.runningVersion = runningVersion
        self.automaticUpdatePresenter = BrowserAutomaticSoftwareUpdatePresenter(
            model: model
        )
        super.init()
    }

    func show(
        _ request: SPUUpdatePermissionRequest,
        reply: @escaping @Sendable (SUUpdatePermissionResponse) -> Void
    ) {
        model.presentPermissionRequest { isEnabled in
            reply(
                SUUpdatePermissionResponse(
                    automaticUpdateChecks: isEnabled,
                    sendSystemProfile: false
                )
            )
        }
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        model.presentChecking(cancellation: cancellation)
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem,
        state: SPUUserUpdateState,
        reply: @escaping @Sendable (SPUUserUpdateChoice) -> Void
    ) {
        guard isNewerThanRunning(appcastItem) else {
            reply(.dismiss)
            updateCycleDidFinish?()
            return
        }
        model.presentUpdate(
            title: appcastItem.title
                ?? "Crest \(appcastItem.displayVersionString)",
            version: appcastItem.displayVersionString,
            build: appcastItem.versionString,
            releaseNotes: appcastItem.itemDescription,
            informationURL: appcastItem.infoURL,
            isInformationOnly: appcastItem.isInformationOnlyUpdate,
            allowsOfferRefresh: state.stage == .notDownloaded,
            install: { reply(.install) },
            skip: { reply(.skip) },
            dismiss: { reply(.dismiss) }
        )
        updateWasFound?()
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        guard let releaseNotes = String(data: downloadData.data, encoding: .utf8)
        else {
            model.presentReleaseNotesFailure(
                "Release notes were downloaded in an unsupported text encoding."
            )
            return
        }
        model.setReleaseNotes(releaseNotes)
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        model.presentReleaseNotesFailure(
            "Release notes could not be loaded: \(error.localizedDescription)"
        )
    }

    func showUpdateNotFoundWithError(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        model.presentNoUpdate(
            message: noUpdateMessage(error),
            acknowledgement: acknowledgement
        )
    }

    func showUpdaterError(
        _ error: any Error,
        acknowledgement: @escaping () -> Void
    ) {
        model.presentError(
            message: updateErrorMessage(error),
            acknowledgement: acknowledgement
        )
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        model.presentDownload(cancellation: cancellation)
    }

    func showDownloadDidReceiveExpectedContentLength(
        _ expectedContentLength: UInt64
    ) {
        model.setExpectedDownloadLength(expectedContentLength)
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        model.receiveDownloadedBytes(length)
    }

    func showDownloadDidStartExtractingUpdate() {
        model.presentExtraction()
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        model.setExtractionProgress(progress)
    }

    func showReady(
        toInstallAndRelaunch reply: @escaping @Sendable (SPUUserUpdateChoice) -> Void
    ) {
        model.presentReadyToInstall(
            install: { reply(.install) },
            cancel: { reply(.skip) }
        )
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool,
        retryTerminatingApplication: @escaping () -> Void
    ) {
        model.presentInstalling(
            applicationTerminated: applicationTerminated,
            retryTermination: retryTerminatingApplication
        )
    }

    func showUpdateInstalledAndRelaunched(
        _ relaunched: Bool,
        acknowledgement: @escaping () -> Void
    ) {
        model.presentInstalled(
            relaunched: relaunched,
            acknowledgement: acknowledgement
        )
    }

    func dismissUpdateInstallation() {
        model.dismissInstallation()
    }

    func showUpdateInFocus() {
        // The sidebar source is authoritative and immediately replays its
        // current card whenever a browser window mounts a widget host.
    }

    func updater(
        _ updater: SPUUpdater,
        didFinishUpdateCycleFor updateCheck: SPUUpdateCheck,
        error: (any Error)?
    ) {
        updateCycleDidFinish?()
    }

    func updater(
        _ updater: SPUUpdater,
        willDownloadUpdate item: SUAppcastItem,
        with request: NSMutableURLRequest
    ) {
        automaticUpdatePresenter.downloadDidBegin(
            BrowserSoftwareUpdateMetadata(appcastItem: item)
        )
    }

    func updater(
        _ updater: SPUUpdater,
        failedToDownloadUpdate item: SUAppcastItem,
        error: any Error
    ) {
        automaticUpdatePresenter.updateDidFail(error)
    }

    func updater(
        _ updater: SPUUpdater,
        willExtractUpdate item: SUAppcastItem
    ) {
        automaticUpdatePresenter.extractionDidBegin(
            BrowserSoftwareUpdateMetadata(appcastItem: item)
        )
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        // A prepared update older than this build is a leftover of the copy that
        // downloaded it. Refusing it here also stops Sparkle installing it on the
        // next normal quit.
        guard isNewerThanRunning(item) else { return false }
        automaticUpdatePresenter.installationDidBecomeReady(
            BrowserSoftwareUpdateMetadata(appcastItem: item),
            installAndRelaunch: immediateInstallHandler
        )
        // Crest owns the immediate-restart affordance. Sparkle still installs
        // this prepared update whenever the application terminates normally.
        return true
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        automaticUpdatePresenter.updateDidFail(error)
    }

    /// Refusing here aborts the cycle and discards the resumed download, which
    /// is how a stale prepared install gets cleared without reaching into
    /// Sparkle's cache.
    func updater(
        _ updater: SPUUpdater,
        shouldProceedWithUpdate updateItem: SUAppcastItem,
        updateCheck: SPUUpdateCheck
    ) throws {
        guard isNewerThanRunning(updateItem) else {
            throw NSError(
                domain: "com.pauldavis.crest.software-update",
                code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "Crest \(updateItem.displayVersionString) is older than the running \(runningVersion ?? "build") and was discarded."
                ]
            )
        }
    }

    /// Whether an offered — or already downloaded and waiting — update is
    /// actually newer than the Crest that is running.
    ///
    /// Sparkle keeps a prepared update in the host bundle's cache, and the next
    /// process to start from that bundle resumes it. A build whose
    /// `MARKETING_VERSION` has since moved ahead of the cached one is then told
    /// it is "Ready to Install" a Crest older than itself, and accepting that
    /// would silently downgrade. Sparkle's own comparison is against the
    /// bundle's recorded version, so the running version has to be checked here.
    ///
    /// Absent or unparseable versions are treated as newer: the guard exists to
    /// catch a stale cache, never to block a legitimate update it cannot read.
    private func isNewerThanRunning(_ item: SUAppcastItem) -> Bool {
        let offered = item.displayVersionString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            !offered.isEmpty,
            let running = runningVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
            !running.isEmpty
        else { return true }
        return offered.compare(running, options: .numeric) == .orderedDescending
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        channel.allowedSparkleChannels
    }

    func feedURLString(for updater: SPUUpdater) -> String? {
        feedURLOverride?.absoluteString ?? channel.customFeedURL?.absoluteString
    }

    private func noUpdateMessage(_ error: any Error) -> String {
        let error = error as NSError
        return [error.localizedDescription, error.localizedRecoverySuggestion]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private func updateErrorMessage(_ error: any Error) -> String {
        let error = error as NSError
        return [error.localizedDescription, error.localizedRecoverySuggestion]
            .compactMap { $0 }
            .joined(separator: " ")
    }
}
