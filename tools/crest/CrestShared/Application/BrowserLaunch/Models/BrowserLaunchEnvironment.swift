import Foundation

struct BrowserLaunchEnvironment: Equatable, Sendable {
    /// Opens the launch's windows without taking focus, for a tool that
    /// starts Crest in the background.
    let launchesInBackground: Bool
    let explicitlyRequiresIsolation: Bool
    let persistentIsolationID: String?
    let isolatedCloudSyncID: String?
    let requestsIsolatedCloudSync: Bool
    let resetsSession: Bool
    let presentsShowcaseSession: Bool
    let usesInMemoryCredentialVault: Bool
    let forcesOnboardingWelcome: Bool
    let forcesMacOnboardingSetup: Bool
    let forcesMobileOnboardingSetup: Bool
    let softwareUpdateWidgetFixture: String?
    let isolatedSoftwareUpdateFeedURL: URL?
    let isXCTestRuntime: Bool
    let isSwiftUIPreviewRuntime: Bool
    /// Whether this launch stays out of the installed profile. The core decides
    /// from the flags above.
    private(set) var requiresIsolation = true
    /// Keeps page and extension web storage in the same privacy class: both
    /// forget, unless a named isolated profile persists both.
    private(set) var usesEphemeralProfileStorage = true
    /// False only under the test runtime.
    private(set) var presentsInstalledApplicationUI = false

    init(
        values: [String: String],
        isXCTestRuntime: Bool,
        isSwiftUIPreviewRuntime: Bool = false
    ) {
        launchesInBackground = Self.isEnabled(.backgroundLaunch, in: values)
        explicitlyRequiresIsolation = Self.isEnabled(.isolatedSession, in: values)
        persistentIsolationID = values[Key.persistentIsolationID.rawValue]
            .flatMap(Self.normalizedIsolationID)
        requestsIsolatedCloudSync = values["CREST_ISOLATED_CLOUD_SYNC_ID"] != nil
        isolatedCloudSyncID = values["CREST_ISOLATED_CLOUD_SYNC_ID"].flatMap { value in
            guard (1...48).contains(value.count),
                value.allSatisfy({
                    $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-")
                })
            else { return nil }
            return value
        }
        resetsSession = Self.isEnabled(.resetSession, in: values)
        presentsShowcaseSession = Self.isEnabled(.showcaseSession, in: values)
        usesInMemoryCredentialVault = Self.isEnabled(
            .useInMemoryCredentials,
            in: values
        )
        forcesOnboardingWelcome = Self.isEnabled(.showOnboarding, in: values)
        forcesMacOnboardingSetup = Self.isEnabled(.showSetup, in: values)
        forcesMobileOnboardingSetup = Self.isEnabled(
            .forceOnboardingSetup,
            in: values
        )
        softwareUpdateWidgetFixture =
            values[
                Key.softwareUpdateWidgetFixture.rawValue
            ]
        isolatedSoftwareUpdateFeedURL = Self.loopbackSoftwareUpdateFeedURL(
            values[Key.softwareUpdateTestFeedURL.rawValue]
        )
        self.isXCTestRuntime = isXCTestRuntime
        self.isSwiftUIPreviewRuntime = isSwiftUIPreviewRuntime
        // Isolation is decided before any core exists, so the core answers it
        // without an app.
        let plan =
            (try? CrestCore.answer(LaunchIsolation(platform: .current, environment: coreEnvironment)))
            ?? LaunchDecision.unavailable
        requiresIsolation = plan.requiresIsolation
        usesEphemeralProfileStorage = plan.usesEphemeralProfileStorage
        presentsInstalledApplicationUI = plan.presentsInstalledApplicationUI
    }

    /// The preferences domain a named isolated profile persists into.
    ///
    /// Every owner of that profile's state — the browser session, the
    /// credential vault prefix, the extension registry — is addressed through
    /// this one name, so a relaunch with the same
    /// `CREST_ISOLATED_PERSISTENCE_ID` finds all of it again and none of it
    /// lands in the installed app's own domain.
    static func isolatedDefaultsSuiteName(isolationID: String) -> String {
        "\(ProductIdentity.serviceNamespace).isolated.\(isolationID)"
    }

    private static func isEnabled(
        _ key: Key,
        in values: [String: String]
    ) -> Bool {
        values[key.rawValue] == "1"
    }

    private static func normalizedIsolationID(_ rawValue: String) -> String? {
        let normalized = rawValue.lowercased().filter {
            $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")
        }
        guard !normalized.isEmpty else { return nil }
        return String(normalized.prefix(48))
    }

    private static func loopbackSoftwareUpdateFeedURL(_ value: String?) -> URL? {
        guard let value, var components = URLComponents(string: value) else {
            return nil
        }
        let loopbackHosts = ["127.0.0.1", "localhost", "::1"]
        guard
            components.scheme?.lowercased() == "http",
            components.user == nil,
            components.password == nil,
            let host = components.host?.lowercased(),
            loopbackHosts.contains(host),
            !components.path.isEmpty
        else { return nil }
        components.fragment = nil
        return components.url
    }

    private enum Key: String {
        case backgroundLaunch = "CREST_BACKGROUND_LAUNCH"
        case isolatedSession = "CREST_ISOLATED_SESSION"
        case persistentIsolationID = "CREST_ISOLATED_PERSISTENCE_ID"
        case resetSession = "CREST_RESET_SESSION"
        case showcaseSession = "CREST_SHOWCASE_SESSION"
        case useInMemoryCredentials = "CREST_USE_IN_MEMORY_CREDENTIALS"
        case showOnboarding = "CREST_SHOW_ONBOARDING"
        case showSetup = "CREST_SHOW_SETUP"
        case forceOnboardingSetup = "CREST_FORCE_ONBOARDING_SETUP"
        case softwareUpdateWidgetFixture = "CREST_UPDATE_WIDGET_FIXTURE"
        case softwareUpdateTestFeedURL = "CREST_UPDATE_TEST_FEED_URL"
    }
}
