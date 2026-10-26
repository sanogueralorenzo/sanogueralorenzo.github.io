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
    let performanceBaseURLString: String?
    let performanceTabCount: String?
    let performanceHeavySession: Bool
    let performanceRunID: String
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
        performanceBaseURLString = values[Key.performanceBaseURL.rawValue]
        performanceTabCount = values[Key.performanceTabCount.rawValue]
        performanceHeavySession = Self.isEnabled(
            .performanceHeavySession,
            in: values
        )
        performanceRunID =
            values[Key.performanceRunID.rawValue]
            ?? Defaults.performanceRunID
        isolatedSoftwareUpdateFeedURL = Self.loopbackSoftwareUpdateFeedURL(
            values[Key.softwareUpdateTestFeedURL.rawValue]
        )
        self.isXCTestRuntime = isXCTestRuntime
        self.isSwiftUIPreviewRuntime = isSwiftUIPreviewRuntime
        // Isolation is decided before any core exists, so the core answers it
        // without an app.
        let plan =
            (try? CrestCore.answer(LaunchIsolation(environment: coreEnvironment)))
            ?? LaunchDecision.unavailable
        requiresIsolation = plan.requiresIsolation
        usesEphemeralProfileStorage = plan.usesEphemeralProfileStorage
        presentsInstalledApplicationUI = plan.presentsInstalledApplicationUI
    }

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
        case performanceBaseURL = "CREST_PERFORMANCE_BASE_URL"
        case performanceTabCount = "CREST_PERFORMANCE_TAB_COUNT"
        case performanceHeavySession = "CREST_PERFORMANCE_HEAVY_SESSION"
        case performanceRunID = "CREST_PERFORMANCE_RUN_ID"
        case softwareUpdateTestFeedURL = "CREST_UPDATE_TEST_FEED_URL"
    }

    private enum Defaults {
        static let performanceRunID = "release-soak"
    }
}
