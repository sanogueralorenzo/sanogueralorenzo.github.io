using CrestCore.Application;

namespace CrestCore.Contracts;

/// Removes every address a Space's history holds that was visited within
/// `Range`, ending now; an address visited earlier too goes with its earlier
/// visits. Without a Space it clears every Space this process may read,
/// passing over one that is locked or being deleted.
public sealed record ClearHistory(Guid WorkspaceId, Guid? SpaceId, BrowsingDataRange Range) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        IEnumerable<SpaceState> spaces = SpaceId is { } spaceId
            ? [workspace.Editable(turn.Basis, spaceId)] : workspace.EditableSpaces(turn.Basis);
        var since = Range.Since(turn.Now);
        var cleared = spaces.Select(space => space.WithoutHistory(entry => since is null || entry.LastVisitedAt >= since));
        return new(turn.Basis.Replacing([.. cleared]), SyncStaging.Deletion);
    }

    #endregion
}
