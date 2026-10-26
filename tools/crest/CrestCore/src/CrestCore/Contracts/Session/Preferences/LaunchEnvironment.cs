namespace CrestCore.Contracts;

/// What the platform read from its launch environment. Each flag is already
/// parsed: a fixture flag is on only for its exact enabled marker, and an
/// update test feed only when it is a loopback address.
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
    bool RunsPerformanceHarness,
    bool UsesUpdateTestFeed) {
    #region Static Variables

    /// An installed launch that asks for nothing special.
    public static LaunchEnvironment Installed { get; } = new(false, false, false, false, false, false, false, false, false);

    #endregion

    #region Variables

    /// Every test, preview, fixture and review launch is isolated.
    internal bool RequiresIsolation => IsTestRuntime || IsPreviewRuntime || RequestsIsolatedSession
        || RequestsIsolatedCloudSync || ResetsSession || PresentsShowcase
        || RunsPerformanceHarness || UsesUpdateTestFeed;

    #endregion

    #region Actions - Launch

    /// Isolation and presentation for this launch, before any session is opened.
    internal LaunchDecision Plan() => new(RequiresIsolation, RequiresIsolation && !HasNamedProfile, !IsTestRuntime);

    #endregion
}
