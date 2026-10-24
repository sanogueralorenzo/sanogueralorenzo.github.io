using CrestCore.Application;

namespace CrestCore.Contracts;

/// Makes a Space the one a launch opens.
public sealed record SetDefaultSpace(Guid WorkspaceId, Guid SpaceId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var space = workspace.Editable(turn.Basis, SpaceId);
        return new(turn.Basis.DefaultSpaceId == space.Id ? turn.Basis : turn.Basis with { DefaultSpaceId = space.Id }, SyncStaging.Edit);
    }

    #endregion
}
