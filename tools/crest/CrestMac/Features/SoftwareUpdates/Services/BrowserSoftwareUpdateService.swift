import Foundation
import Observation
import Sparkle

@MainActor
@Observable
final class BrowserSoftwareUpdateService {
    // MARK: - Static Variables

    static let channelPreferenceKey = "crest.software-update.channel"
    static let bundledChannelPreferenceKey =
        "crest.software-update.bundled-channel"
    static let defaultChannelInfoKey = "CrestDefaultUpdateChannel"

    // MARK: - Variables

    let model: BrowserSoftwareUpdateModel
    let widgetSource: BrowserSoftwareUpdateWidgetSource
    private(set) var isEnabled: Bool
    private(set) var startErrorDescription: String?
    var channel: BrowserSoftwareUpdateChannel {
        didSet {
            userDriver.channel = channel
            preferences?.set(channel.name, forKey: Self.channelPreferenceKey)
            guard isEnabled else { return }
            refreshCoordinator.channelDidChange()
        }
    }

    @ObservationIgnored private let preferences: UserDefaults?
    @ObservationIgnored private let userDriver: BrowserSoftwareUpdateUserDriver
    @ObservationIgnored private let updater: SPUUpdater
    @ObservationIgnored private let refreshCoordinator: BrowserSoftwareUpdateRefreshCoordinator

    var automaticallyChecksForUpdates: Bool {
        updater.automaticallyChecksForUpdates
    }

    var automaticallyDownloadsUpdates: Bool {
        updater.automaticallyDownloadsUpdates
    }

    // MARK: - Initializers

    init(
        isEnabled: Bool,
        preferences: UserDefaults? = .standard,
        defaultChannel: BrowserSoftwareUpdateChannel? = nil,
        feedURLOverride: URL? = nil
    ) {
        let bundledDefaultChannel =
            defaultChannel
            ?? BrowserSoftwareUpdateChannel.named(
                Bundle.main.object(
                    forInfoDictionaryKey: Self.defaultChannelInfoKey
                ) as? String ?? ""
            )
            ?? .stable
        let channel = Self.launchChannel(
            bundledDefault: bundledDefaultChannel,
            preferences: preferences
        )
        let widgetSource = BrowserSoftwareUpdateWidgetSource()
        let model = BrowserSoftwareUpdateModel(widgetSource: widgetSource)
        let userDriver = BrowserSoftwareUpdateUserDriver(
            model: model,
            channel: channel,
            feedURLOverride: feedURLOverride
        )
        self.model = model
        self.widgetSource = widgetSource
        self.isEnabled = isEnabled
        self.preferences = preferences
        self.channel = channel
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
        startUpdater()
    }

    // MARK: - Actions - Checking

    /// A check the person asked for, which also brings back a card they hid.
    func checkForUpdates() {
        guard isEnabled else {
            model.presentError(
                message: "Update checks are disabled in this isolated Crest session.",
                acknowledgement: {}
            )
            return
        }
        model.reveal()
        refreshCoordinator.checkForUpdates()
    }

    func applicationDidBecomeActive() {
        guard isEnabled else { return }
        refreshCoordinator.applicationDidBecomeActive()
    }

    // MARK: - Actions - Fixtures

    /// Presents updater states for an explicitly isolated verification launch.
    /// It never starts Sparkle or reads an appcast, and is deliberately absent
    /// from the production launch path.
    func presentIsolatedSidebarWidgetFixture(_ description: String) {
        guard !isEnabled else { return }
        let components = description.split(
            separator: ":",
            maxSplits: 2,
            omittingEmptySubsequences: true
        ).map(String.init)
        let fixture = BrowserSoftwareUpdateFixture.named(components.first ?? "available")
        let version = components.count > 1 ? components[1] : "0.5.99"
        let build = components.count > 2 ? components[2] : "599"
        let releaseNotes = """
            ## What's New

            - Software update progress stays visible in the sidebar.
            - Release notes open only when you ask to review them.
            """
        model.presentUpdate(
            title: "Crest \(version)",
            version: version,
            build: build,
            releaseNotes: releaseNotes,
            isInformationOnly: false,
            isFixture: true,
            install: {},
            skip: {}
        )
        fixture.present(on: model, version: version, build: build, releaseNotes: releaseNotes)
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

    private static func launchChannel(
        bundledDefault: BrowserSoftwareUpdateChannel,
        preferences: UserDefaults?
    ) -> BrowserSoftwareUpdateChannel {
        let previousBundledChannel = preferences?.string(
            forKey: bundledChannelPreferenceKey
        )
        guard previousBundledChannel == bundledDefault.name else {
            preferences?.set(
                bundledDefault.name,
                forKey: bundledChannelPreferenceKey
            )
            preferences?.set(
                bundledDefault.name,
                forKey: channelPreferenceKey
            )
            return bundledDefault
        }
        return BrowserSoftwareUpdateChannel.named(
            preferences?.string(
                forKey: channelPreferenceKey
            ) ?? ""
        ) ?? bundledDefault
    }

    // MARK: - Mutators

    func setAutomaticallyChecksForUpdates(_ isEnabled: Bool) {
        updater.automaticallyChecksForUpdates = isEnabled
    }

    func setAutomaticallyDownloadsUpdates(_ isEnabled: Bool) {
        updater.automaticallyDownloadsUpdates = isEnabled
    }
}
