using CrestCore.Application;

namespace CrestCore.Contracts;

/// Moves a tab from the window `WindowId` to the window
/// `DestinationWindowId`, which then shows it in its Space.
///
/// When both windows show this workspace the tab stays where it is. When the
/// destination shows another workspace, one that borrows this one's Space or
/// whose Space this one borrows, the tab leaves this workspace and joins that
/// one's open tabs after the tab its window shows. Both workspaces change
/// together, the one that keeps a file saved with its sync journal before the
/// intent returns, or neither changes; the window the tab left shows the tab
/// it showed before. Refused with `WindowNotOpen` for a destination window
/// that is gone, `PrivateWorkspaceBoundary` between private and other
/// browsing, `UnrelatedWorkspaces` for workspaces that share no Space,
/// `UnknownSpace` when the destination does not hold the tab's Space,
/// `TabAlreadyExists` when it holds the tab, and `TabLimitReached`.
public sealed record MoveTabToWindow(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId, Guid DestinationWindowId)
    : SessionIntent(WorkspaceId) {
    #region Actions - Session

    /// Both windows show this workspace, so the tab stays where it is: the
    /// window it moves to shows it and its Space, and the tab's use is
    /// recorded, as showing a tab records it.
    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        var space = workspace.Editable(turn.Basis, SpaceId);
        if (space.Tabs.All(tab => tab.Id != TabId)) throw new Rejected(new UnknownTab(TabId));
        var followUp = new WindowFollowUp(workspace.IssuingWindow(DestinationWindowId)).ShowTab(space.Id, TabId).ShowSpace(space.Id);
        var used = space with { Tabs = [.. space.Tabs.Select(tab => tab.Id == TabId ? tab with { LastActivatedAt = turn.Now } : tab)] };
        return new(NativeSessionAuthority.Replacing(turn.Basis, used), SyncStaging.TabUse, followUp);
    }

    /// When the window it moves to shows another workspace, the tab leaves
    /// this one for that one; both change together or neither does.
    internal override bool MovedAcross(NativeSessionAuthority workspace, DateTimeOffset now, bool commits) {
        if (workspace.Receiving(this) is not { } receiving) return false;
        workspace.MovingAcross(receiving, this, now, commits);
        return true;
    }

    #endregion
}
