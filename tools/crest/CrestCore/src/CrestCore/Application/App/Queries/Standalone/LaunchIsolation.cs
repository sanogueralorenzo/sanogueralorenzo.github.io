using CrestCore.Application;

namespace CrestCore.Contracts;

/// How this launch treats the person's data, decided before any session
/// exists: whether it stays out of the installed profile, whether page and
/// extension storage forget, and whether it shows the installed app's UI. The
/// result reads no state, so the host asks it before it makes an app.
public sealed record LaunchIsolation(LaunchEnvironment Environment) : StandaloneQuery<LaunchDecision> {
    #region Actions - Answering

    internal override LaunchDecision Answer(StandaloneContext context) =>
        Environment.Plan();

    #endregion
}
