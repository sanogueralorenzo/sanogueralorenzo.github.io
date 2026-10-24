using CrestCore.Application;

namespace CrestCore.Contracts;

/// Sets whether a Space offers to save and fill passwords, which reaches the
/// person's other devices, and where it keeps them, which stays on this one.
public sealed record SetCredentialPreferences(Guid WorkspaceId, Guid SpaceId, CredentialPreferences Preferences)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        return workspace.SettingSpace(turn.Basis, workspace.Editable(turn.Basis, SpaceId),
            settings => settings with {
                CredentialPreferences = Preferences,
                CredentialsEnabledModifiedAt = Preferences.IsEnabled == settings.CredentialPreferences.IsEnabled
                    ? settings.CredentialsEnabledModifiedAt : turn.Now
            },
            SyncStaging.Protection);
    }

    #endregion
}
