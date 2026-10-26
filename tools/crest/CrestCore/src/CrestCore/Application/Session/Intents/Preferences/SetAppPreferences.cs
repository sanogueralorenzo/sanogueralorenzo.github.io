using CrestCore.Application;

namespace CrestCore.Contracts;

/// Sets the app-wide behavior preferences. The persistent workspace keeps
/// them on this device; they never sync.
public sealed record SetAppPreferences(Guid WorkspaceId, AppPreferences Preferences) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequirePreferenceOwner();
        return workspace.Preferred(turn.Basis, Preferences);
    }

    #endregion
}
