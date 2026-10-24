namespace CrestCore.Contracts;

/// What the platform read from its launch environment. Each flag is already
/// parsed: a fixture flag is on only for its exact enabled marker, a
/// performance harness is present when its base address is supplied at all,
/// and an update test feed only when it is a loopback address.
/// `HasNamedProfile` marks a named isolated profile, which persists its own
/// state across relaunches. These facts decide which launches must stay out
/// of the installed profile, and what a window opens with.
public sealed record LaunchEnvironment(
    bool IsTestRuntime,
    bool IsPreviewRuntime,
    bool RequestsIsolatedSession,
    bool HasNamedProfile,
    bool RequestsIsolatedCloudSync,
    bool ResetsSession,
    bool PresentsShowcase,
    bool UsesInMemoryCredentials,
    bool ForcesOnboardingWelcome,
    bool ForcesDesktopSetup,
    bool ForcesMobileSetup,
    bool RunsPerformanceHarness,
    bool UsesUpdateTestFeed) {
    #region Static Variables

    /// An installed launch that asks for nothing special.
    public static LaunchEnvironment Installed { get; } = new(false, false, false, false, false, false, false, false, false, false,
        false, false, false);

    #endregion

    #region Variables

    /// Every test, preview, fixture, review and performance launch is isolated.
    internal bool RequiresIsolation => IsTestRuntime || IsPreviewRuntime || RequestsIsolatedSession
        || RequestsIsolatedCloudSync || ResetsSession || PresentsShowcase
        || UsesInMemoryCredentials || ForcesOnboardingWelcome || ForcesDesktopSetup
        || ForcesMobileSetup || RunsPerformanceHarness || UsesUpdateTestFeed;

    #endregion

    #region Actions - Launch

    /// The launch on `platform`. `storedStartup` is the saved preference, null
    /// when absent or unreadable. `hasActiveLaunchGate` is true while
    /// first-run setup owns the initial destination.
    internal LaunchDecision Plan(DevicePlatform platform, StartupBehavior? storedStartup, bool hasActiveLaunchGate) {
        bool isolated = RequiresIsolation;
        return new(isolated, isolated && !HasNamedProfile, !IsTestRuntime,
            Startup(platform, isolated, storedStartup, hasActiveLaunchGate));
    }

    /// The mobile showcase always opens on the Start Page. Setup and isolated
    /// launches restore the last active tab so a fixture opens where it was
    /// staged; everyone else gets their saved choice, or the documented
    /// default for a person who never chose.
    private StartupBehavior Startup(DevicePlatform platform, bool isolated, StartupBehavior? stored, bool hasActiveLaunchGate) {
        if (platform.ShowcaseOpensStartPage && PresentsShowcase) return StartupBehavior.ShowStartPage;
        if (hasActiveLaunchGate || isolated) return StartupBehavior.LastActiveTab;
        return stored ?? AppPreferences.Default.Startup;
    }

    #endregion
}
