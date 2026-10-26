using CrestCore.Application;

namespace CrestCore.Contracts;

/// Puts the workspace's Spaces in the order `SpaceIds` lists, which names
/// each of them once.
public sealed record ReorderSpaces(Guid WorkspaceId, IReadOnlyList<Guid> SpaceIds) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequireOwnedSpaces();
        var byId = turn.Basis.Spaces.ToDictionary(space => space.Id);
        if (SpaceIds.Count != byId.Count || SpaceIds.Distinct().Count() != byId.Count || SpaceIds.Any(id => !byId.ContainsKey(id)))
            throw new Rejected(new InvalidSpaceOrder());
        return new(turn.Basis.Spaces.Select(space => space.Id).SequenceEqual(SpaceIds)
            ? turn.Basis : turn.Basis with { Spaces = [.. SpaceIds.Select(id => byId[id])] }, SyncStaging.Edit);
    }

    #endregion
}
