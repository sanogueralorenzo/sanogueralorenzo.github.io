using CrestCore.Application;

namespace CrestCore.Contracts;

/// Gives the persistent workspace the preferences the settings kept before the
/// core owned them, once: a workspace that already holds preferences keeps
/// them, so a later launch never imports over a choice.
public sealed record ImportAppPreferences(Guid WorkspaceId, LegacyAppPreferences Legacy) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// An import applies only while the session holds no preferences, so a
    /// later launch never imports over a choice.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequirePreferenceOwner();
        return turn.Basis.AppPreferences is not null ? new(turn.Basis, Staging: null)
            : workspace.Preferred(turn.Basis, StoredSessionCodec.ImportAppPreferences(Legacy));
    }

    #endregion
}
