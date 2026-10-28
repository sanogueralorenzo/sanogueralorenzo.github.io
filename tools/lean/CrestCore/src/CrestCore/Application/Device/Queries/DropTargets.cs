using CrestCore.Application;

namespace CrestCore.Contracts;

/// Where a lift of `Selection` in a window's sidebar may drop, answered once as
/// the lift begins: the rule that refuses the lift, the lists and Spaces it may
/// reach, and whether it may join the cards on show. Each list or Space drop is
/// checked as the lift reaches it. A drop may still be refused when it lands,
/// since the session can change while the lift is held; its commit decides.
public sealed record DropTargets(Guid WorkspaceId, Guid WindowId, Guid SpaceId, TabSelection Selection) : Query<DropTargetList> {
    #region Actions - Answering

    /// Where a lift in a window's sidebar may drop: the lists and Spaces it
    /// may reach, and the cards on show, whose join is checked now. The lists
    /// and Spaces are checked as the lift reaches them.
    internal override DropTargetList Answer(CrestApp app) {
        var window = app.Device.Opened(WindowId);
        var authority = app.Device.Workspace(WorkspaceId);
        try {
            authority.CheckLift(WindowId, SpaceId, Selection);
        } catch (Rejected refused) {
            return new(refused.Rejection, [], [], Split: null, []);
        }
        var session = authority.Current;
        var space = session.Spaces.First(candidate => candidate.Id == SpaceId);
        var (workspaceId, windowId, spaceId, selection) = (WorkspaceId, WindowId, SpaceId, Selection);
        ListDropTarget[] lists = [.. space.Sidebar.Lists.Select(list => new ListDropTarget(list.Section, list.FolderId))];
        Guid[] spaces = [.. Window.Showable(session).Where(other => other.Id != spaceId).Select(other => other.Id)];
        Guid? shown;
        lock (app.Device.Gate) shown = window.Tab(spaceId);
        var split = shown is { } target
            ? new SplitDropTarget(target, Device.Refusal(authority,
                new DropIntoSplit(workspaceId, windowId, spaceId, selection, target, Index: null), app.Clock.Now, app.Pages))
            : null;
        // Every candidate passes the rule a drop checks of its tab, so the first
        // answers for all of them what the lift allows.
        var lifted = selection.MemberTabIds.ToHashSet();
        var tabs = space.Tabs.ToDictionary(tab => tab.Id);
        Guid[] around = [.. space.Sidebar.Lists.Where(list => list.FolderId is null && !list.Section.IsDurable)
            .SelectMany(list => list.Rows)
            .Where(row => row.Kind == SidebarRowKind.Tab && tabs[row.Id].SplitGroupId is null && !lifted.Contains(row.Id))
            .Select(row => row.Id)];
        if (around.Length > 0
            && Device.Refusal(authority, new DropAroundTab(workspaceId, windowId, spaceId, selection, around[0]), app.Clock.Now,
                app.Pages) is not null)
            around = [];
        return new(Refusal: null, lists, spaces, split, around);
    }

    #endregion
}
