using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Adds a Space after the others, with a profile of its own and one Start
/// Page tab. The core names it and gives it its symbol, accent and look; a
/// private workspace's Space never offers to save passwords. The window that
/// asked shows it, when that window is open over the workspace.
public sealed record CreateSpace(Guid WorkspaceId, Guid WindowId, Guid SpaceId) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        if (turn.Basis.Spaces.Any(space => space.Id == SpaceId)) throw new Rejected(new SpaceAlreadyExists(SpaceId));
        if (turn.Basis.Spaces.Count >= SessionState.MaximumSpaces) throw new Rejected(new SpaceLimitReached(SessionState.MaximumSpaces));
        var space = SpaceTemplate.For(workspace.Kind.IsPrivate)
            .Make(SpaceId, turn.Ids.Next(), turn.Ids.Next, turn.Basis.Spaces.Count + 1, turn.Now);
        // A new Space is the one its window shows next, on its only tab.
        var followUp = new WindowFollowUp(workspace.IssuingWindow(WindowId)).ShowSpace(space.Id).ShowTab(space.Id, space.Tabs[0].Id);
        return new(turn.Basis with { Spaces = [.. turn.Basis.Spaces, space] }, SyncStaging.Creation, followUp);
    }

    #endregion
}
