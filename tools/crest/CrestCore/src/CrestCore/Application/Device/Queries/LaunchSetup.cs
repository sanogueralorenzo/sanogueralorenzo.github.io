using CrestCore.Application;

namespace CrestCore.Contracts;

/// The setup a launch in `Environment` holds its windows back for, which
/// stays until setup finishes in this run: first-run setup on a device that
/// has not completed it, or in a launch that forces it; else none.
public sealed record LaunchSetup(LaunchEnvironment Environment) : Query<LaunchSetupGate> {
    #region Actions - Answering

    internal override LaunchSetupGate Answer(CrestApp app) => new(app.Device.LaunchSetup(Environment, app.Device.Platform));

    #endregion
}
