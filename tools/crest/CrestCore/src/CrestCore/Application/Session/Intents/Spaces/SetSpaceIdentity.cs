using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Renames a Space. A blank name reads as "Untitled Space".
public sealed record SetSpaceIdentity(Guid WorkspaceId, Guid SpaceId, string Name)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var space = workspace.Editable(turn.Basis, SpaceId);
        var name = SpaceCustomization.Chosen(Name);
        return workspace.SettingSpace(turn.Basis, space, settings => settings with {
            Name = name
        }, SyncStaging.Edit);
    }

    #endregion
}
