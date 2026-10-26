using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

public sealed record BeginDeletingSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid OperationId)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Records the deletion, which leaves the Space as it is until it is
    /// removed. The window showing a Space that is going away moves to the
    /// first one that stays.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var (space, pending) = workspace.Deleting(turn.Basis, SpaceId);
        if (pending is not null)
            return pending.Id == OperationId
                ? new(turn.Basis, SyncStaging.Withdrawal)
                : throw new Rejected(new WrongDeletionOperation(space.Id));
        SessionState.RequireRemovable(turn.Basis.Spaces.Count - turn.Basis.SpaceDeletions.Count);
        var next = turn.Basis with { SpaceDeletions = [.. turn.Basis.SpaceDeletions, new(OperationId, space.Id, space.ProfileId)] };
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId));
        if (followUp.Window?.ShownSpaceId == space.Id)
            followUp.ShowSpace(next.Spaces.First(candidate => next.PendingDeletion(candidate.Id) is null).Id);
        return new(next, SyncStaging.Withdrawal, followUp);
    }

    #endregion
}
