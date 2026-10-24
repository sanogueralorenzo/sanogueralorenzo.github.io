import Foundation

extension BrowserLaunchEnvironment {
    /// The parsed launch flags, as the core's launch plan reads them.
    var coreEnvironment: LaunchEnvironment {
        LaunchEnvironment(
            isTestRuntime: isXCTestRuntime, isPreviewRuntime: isSwiftUIPreviewRuntime,
            requestsIsolatedSession: explicitlyRequiresIsolation, hasNamedProfile: persistentIsolationID != nil,
            requestsIsolatedCloudSync: requestsIsolatedCloudSync, resetsSession: resetsSession,
            presentsShowcase: presentsShowcaseSession, usesInMemoryCredentials: usesInMemoryCredentialVault,
            forcesOnboardingWelcome: forcesOnboardingWelcome, forcesDesktopSetup: forcesMacOnboardingSetup,
            forcesMobileSetup: forcesMobileOnboardingSetup, runsPerformanceHarness: performanceBaseURLString != nil,
            usesUpdateTestFeed: isolatedSoftwareUpdateFeedURL != nil)
    }
}
