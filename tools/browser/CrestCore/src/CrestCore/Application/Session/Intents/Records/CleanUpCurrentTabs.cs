using CrestCore.Application;

namespace CrestCore.Contracts;

/// Moves the open tabs of a Space that went unused for longer than its
/// cleanup lifetime to its archive, keeping every tab a window shows or a
/// saved window will show, and every tab whose page runs media. Without a
/// Space it cleans up every Space that is not being deleted, locked or not,
/// since cleanup reveals nothing.
public sealed record CleanUpCurrentTabs(Guid WorkspaceId, Guid? SpaceId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        IEnumerable<SpaceState> spaces = SpaceId is { } spaceId
            ? [workspace.Editable(turn.Basis, spaceId, maintains: true)] : workspace.EditableSpaces(turn.Basis, maintains: true);
        var kept = workspace.TabsCleanupKeeps(turn);
        return new(NativeSessionAuthority.Replacing(turn.Basis, [.. spaces.Select(space => workspace.CleanedUp(space, turn.Now, kept))]),
            SyncStaging.Expiry);
    }

    #endregion
}
