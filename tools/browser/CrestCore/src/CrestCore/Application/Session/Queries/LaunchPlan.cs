using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// How this launch treats the person's data and what its first window opens,
/// with the startup choice the persistent workspace keeps. First-run setup
/// that holds the first window back, as the device decides for the launch
/// environment, is an active launch gate.
public sealed record LaunchPlan(Guid WorkspaceId, DevicePlatform Platform, LaunchEnvironment Environment) : Query<LaunchDecision> {
    #region Actions - Answering

    internal override LaunchDecision Answer(CrestApp app) {
        bool gated = Platform.SetupHoldsFirstWindow && app.Device.LaunchSetup(Environment, Platform) is not null;
        return Answer(app.Device.Workspace(WorkspaceId), gated);
    }

    /// How this launch treats the person's data and what its first window
    /// opens, with the startup choice this workspace keeps. Throws `Rejected`
    /// with `PersistentWorkspaceRequired` for any other workspace.
    private LaunchDecision Answer(NativeSessionAuthority workspace, bool gated) {
        lock (NativeSessionAuthority.Gate) {
            workspace.RequirePreferenceOwner();
            return Environment.Plan(Platform, workspace.AcceptedSession.AppPreferences?.Startup, gated);
        }
    }

    #endregion
}
