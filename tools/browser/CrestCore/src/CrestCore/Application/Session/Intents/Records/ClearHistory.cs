using CrestCore.Application;

namespace CrestCore.Contracts;

/// Removes every address a Space's history holds. Without a Space it clears
/// every Space this process may read, passing over one that is locked or being
/// deleted.
public sealed record ClearHistory(Guid WorkspaceId, Guid? SpaceId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        IEnumerable<SpaceState> spaces = SpaceId is { } spaceId
            ? [workspace.Editable(turn.Basis, spaceId)] : workspace.EditableSpaces(turn.Basis);
        return new(NativeSessionAuthority.Replacing(turn.Basis,
                [.. spaces.Select(space => space.History.Count == 0 ? space : space with { History = [] })]),
            SyncStaging.Deletion);
    }

    #endregion
}
