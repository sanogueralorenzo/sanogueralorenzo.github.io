using CrestCore.Application;

namespace CrestCore.Contracts;

/// Moves a tab `Offset` members along its split. Refused with `NoSplitStep`
/// when the step would move nothing: no offset, a step past either end, or a
/// tab in no split.
public sealed record StepSplitMember(Guid WorkspaceId, Guid SpaceId, Guid TabId, int Offset) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) =>
        workspace.Organizing(turn.Basis, SpaceId, SyncStaging.Edit, edited => {
            if (!edited.StepSplitMember(TabId, Offset, turn.Now)) throw new Rejected(new NoSplitStep(TabId, Offset));
        });

    #endregion
}
