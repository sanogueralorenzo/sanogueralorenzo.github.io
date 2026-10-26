using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Replaces everything a private workspace holds with one fresh private
/// Space, which the window that asked shows.
public sealed record ResetPrivateBrowsing(Guid WorkspaceId, Guid WindowId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// A private workspace starts over with one fresh private Space, which
    /// the window that asked shows. Nothing it held ever synced.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        if (!workspace.Kind.IsPrivate) throw new Rejected(new NotPrivateWorkspace(workspace.WorkspaceId));
        var space = SpaceTemplate.Private.Make(turn.Ids.Next(), turn.Ids.Next(), turn.Ids.Next, number: 1, turn.Now);
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId)).ShowSpace(space.Id).ShowTab(space.Id, space.Tabs[0].Id);
        return new(turn.Basis with { Spaces = [space], SpaceDeletions = [], DefaultSpaceId = null }, Staging: null, followUp);
    }

    #endregion
}
