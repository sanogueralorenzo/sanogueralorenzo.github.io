using CrestCore.Application;

namespace CrestCore.Contracts;

/// How this launch treats the person's data, decided before any session
/// exists: whether it stays out of the installed profile, whether page and
/// extension storage forget, and whether it shows the installed app's UI. Its
/// startup answer is the one for a person who never chose; `LaunchPlan` reads
/// the saved choice once a workspace keeps one. It reads no state, so the host
/// asks it before it makes an app.
public sealed record LaunchIsolation(DevicePlatform Platform, LaunchEnvironment Environment) : StandaloneQuery<LaunchDecision> {
    #region Actions - Answering

    internal override LaunchDecision Answer(StandaloneContext context) =>
        Environment.Plan(Platform, storedStartup: null, hasActiveLaunchGate: false);

    #endregion
}
