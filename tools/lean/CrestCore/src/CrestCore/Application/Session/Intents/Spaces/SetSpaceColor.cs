using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Sets the color a Space uses as its identity.
public sealed record SetSpaceColor(Guid WorkspaceId, Guid SpaceId, SpaceColor Color)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var space = workspace.Editable(turn.Basis, SpaceId);
        return workspace.SettingSpace(turn.Basis, space, settings => settings with {
            StoredColor = Color
        }, SyncStaging.Edit);
    }

    #endregion
}
