import Foundation

extension BrowserLaunchEnvironment {
    /// The parsed launch flags, as the core's launch plan reads them.
    var coreEnvironment: LaunchEnvironment {
        LaunchEnvironment(
            isTestRuntime: isXCTestRuntime, isPreviewRuntime: isSwiftUIPreviewRuntime,
            requestsIsolatedSession: explicitlyRequiresIsolation, hasNamedProfile: persistentIsolationID != nil,
            requestsIsolatedCloudSync: requestsIsolatedCloudSync, resetsSession: resetsSession,
            presentsShowcase: presentsShowcaseSession,
            runsPerformanceHarness: performanceBaseURLString != nil,
            usesUpdateTestFeed: isolatedSoftwareUpdateFeedURL != nil)
    }
}
