import Foundation
import Sparkle

@MainActor
protocol BrowserSoftwareUpdateChecking: AnyObject {
    var automaticallyChecksForUpdates: Bool { get set }
    var automaticallyDownloadsUpdates: Bool { get set }
    var sessionInProgress: Bool { get }
    var canCheckForUpdates: Bool { get }
    var lastUpdateCheckDate: Date? { get }

    func checkForUpdates()
    func checkForUpdatesInBackground()
    func resetUpdateCycleAfterShortDelay()
}

extension SPUUpdater: BrowserSoftwareUpdateChecking {}

/// Keeps Crest's refresh intent separate from Sparkle's download, validation,
/// and installation ownership. Sparkle remains the only component that selects,
/// verifies, downloads, resumes, skips, or installs an update.
@MainActor
final class BrowserSoftwareUpdateRefreshCoordinator {
    static let minimumAutomaticCheckInterval: TimeInterval = 60 * 60

    private let updater: any BrowserSoftwareUpdateChecking
    private let model: BrowserSoftwareUpdateModel
    private var pendingCheck: BrowserSoftwareUpdateCheck?
    private var downloadsNextOffer = false
    private var lastAutomaticRefreshRequestDate: Date?

    init(
        updater: any BrowserSoftwareUpdateChecking,
        model: BrowserSoftwareUpdateModel
    ) {
        self.updater = updater
        self.model = model
        model.refreshBeforeDownload = { [weak self] in
            self?.downloadLatestUpdate()
        }
    }

    func updaterDidStart(at date: Date = Date()) {
        requestAutomaticRefreshIfDue(at: date)
    }

    func applicationDidBecomeActive(at date: Date = Date()) {
        requestAutomaticRefreshIfDue(at: date)
    }

    func checkForUpdates() {
        _ = request(.userInitiated)
    }

    func updateWasFound() {
        guard downloadsNextOffer else { return }
        downloadsNextOffer = false
        model.installPresentedUpdate()
    }

    private func downloadLatestUpdate() {
        _ = request(.downloadLatest)
    }

    func channelDidChange() {
        downloadsNextOffer = false
        updater.resetUpdateCycleAfterShortDelay()

        guard updater.sessionInProgress else { return }
        pendingCheck = updater.automaticallyChecksForUpdates ? .background : nil
        guard model.beginRefreshingAvailableUpdate() else {
            pendingCheck = nil
            return
        }
    }

    func updateCycleDidFinish() {
        guard let pendingCheck else {
            downloadsNextOffer = false
            model.finishRefreshIfNeeded()
            return
        }

        self.pendingCheck = nil
        guard start(pendingCheck) else {
            model.finishRefreshIfNeeded()
            return
        }
    }

    private func requestAutomaticRefreshIfDue(at date: Date) {
        guard updater.automaticallyChecksForUpdates else { return }
        let mostRecentCheck = [
            updater.lastUpdateCheckDate,
            lastAutomaticRefreshRequestDate,
        ].compactMap { $0 }.max()
        if let mostRecentCheck {
            guard
                date.timeIntervalSince(mostRecentCheck)
                    >= Self.minimumAutomaticCheckInterval
            else { return }
        }

        guard request(.background) else { return }
        lastAutomaticRefreshRequestDate = date
    }

    @discardableResult
    private func request(_ check: BrowserSoftwareUpdateCheck) -> Bool {
        if let pendingCheck {
            if check.replaces(pendingCheck) {
                self.pendingCheck = check
            }
            return true
        }
        if updater.sessionInProgress {
            pendingCheck = check
            if model.beginRefreshingAvailableUpdate(cancellation: { [weak self] in
                self?.pendingCheck = nil
                self?.downloadsNextOffer = false
            }) {
                return true
            }

            pendingCheck = nil
            if check.isUserInitiated {
                if updater.canCheckForUpdates {
                    updater.checkForUpdates()
                }
            }
            return false
        }

        return start(check)
    }

    private func start(_ check: BrowserSoftwareUpdateCheck) -> Bool {
        guard !updater.sessionInProgress, updater.canCheckForUpdates else {
            return false
        }
        if check.downloadsOffer {
            downloadsNextOffer = true
        }
        check.start(on: updater)
        return true
    }
}
