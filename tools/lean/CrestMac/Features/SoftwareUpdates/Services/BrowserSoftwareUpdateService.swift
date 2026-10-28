import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class BrowserSoftwareUpdateService {
    // MARK: - Variables

    let model: BrowserSoftwareUpdateModel
    private(set) var isEnabled: Bool
    private(set) var startErrorDescription: String?
    @ObservationIgnored private let userDriver: BrowserSoftwareUpdateUserDriver
    @ObservationIgnored private let updater: SPUUpdater
    @ObservationIgnored private let refreshCoordinator: BrowserSoftwareUpdateRefreshCoordinator

    // MARK: - Initializers

    init(
        isEnabled: Bool,
        feedURLOverride: URL? = nil
    ) {
        let model = BrowserSoftwareUpdateModel()
        let userDriver = BrowserSoftwareUpdateUserDriver(
            model: model,
            feedURLOverride: feedURLOverride
        )
        self.model = model
        self.isEnabled = isEnabled
        self.userDriver = userDriver
        let updater = SPUUpdater(
            hostBundle: .main,
            applicationBundle: .main,
            userDriver: userDriver,
            delegate: userDriver
        )
        let refreshCoordinator = BrowserSoftwareUpdateRefreshCoordinator(
            updater: updater,
            model: model
        )
        self.updater = updater
        self.refreshCoordinator = refreshCoordinator
        userDriver.updateCycleDidFinish = { [weak refreshCoordinator] in
            refreshCoordinator?.updateCycleDidFinish()
        }
        userDriver.updateWasFound = { [weak refreshCoordinator] in
            refreshCoordinator?.updateWasFound()
        }

        guard isEnabled else { return }
        updater.automaticallyChecksForUpdates = true
        updater.automaticallyDownloadsUpdates = true
        startUpdater()
    }

    // MARK: - Actions - Checking

    /// A check the person asked for.
    func checkForUpdates() {
        guard isEnabled else {
            model.presentError(
                message: "Update checks are disabled in this isolated Crest session.",
                acknowledgement: {}
            )
            return
        }
        refreshCoordinator.checkForUpdates()
    }

    func applicationDidBecomeActive() {
        guard isEnabled else { return }
        refreshCoordinator.applicationDidBecomeActive()
    }

    // MARK: - Actions - Launch

    private func startUpdater() {
        do {
            try updater.start()
            startErrorDescription = nil
            refreshCoordinator.updaterDidStart()
        } catch {
            isEnabled = false
            startErrorDescription = error.localizedDescription
            model.presentError(
                message: "Crest could not start software updates: \(error.localizedDescription)",
                acknowledgement: {}
            )
        }
    }

}
