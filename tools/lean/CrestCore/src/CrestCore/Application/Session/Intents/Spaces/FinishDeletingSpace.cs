using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Removes a Space whose deletion `OperationId` began, once the platform has
/// erased its profile's data, and saves that before it returns. The Space
/// that takes its place is shown by the window that asked when it showed
/// the removed one.
public sealed record FinishDeletingSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid OperationId)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Removes the Space and its deletion. The Space that takes its place is
    /// where its window goes.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var (space, pending) = workspace.Deleting(turn.Basis, SpaceId);
        if (pending is null || pending.Id != OperationId) throw new Rejected(new WrongDeletionOperation(space.Id));
        SessionState.RequireRemovable(turn.Basis.Spaces.Count);
        var index = turn.Basis.Spaces.ToList().IndexOf(space);
        IReadOnlyList<SpaceState> spaces = [.. turn.Basis.Spaces.Where(candidate => candidate.Id != space.Id)];
        var neighbor = spaces[Math.Min(index, spaces.Count - 1)].Id;
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        if (followUp.Window?.ShownSpaceId == space.Id) followUp.ShowSpace(neighbor);
        return new(turn.Basis with {
            Spaces = spaces,
            SpaceDeletions = [.. turn.Basis.SpaceDeletions.Where(deletion => deletion != pending)]
        }, SyncStaging.Removal, followUp);
    }

    #endregion

}
