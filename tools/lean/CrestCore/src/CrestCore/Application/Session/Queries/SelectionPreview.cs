using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

public sealed record SelectionPreview(Guid WorkspaceId, Guid SpaceId, IReadOnlyList<Guid> TabIds, IReadOnlyList<Guid> FolderIds)
    : Query<SelectedTabs> {
    #region Actions - Answering

    internal override SelectedTabs Answer(CrestApp app) => Answer(app.Device.Workspace(WorkspaceId));

    private SelectedTabs Answer(NativeSessionAuthority workspace) {
        SpaceState space;
        lock (NativeSessionAuthority.Gate) space = workspace.AcceptedSession.KnownSpace(SpaceId);
        var resolved = BrowserTabCollection.Restore(space).Preview(TabIds, FolderIds);
        var positions = space.Sidebar.Positions();
        int Place(Guid id) => positions.GetValueOrDefault(id, int.MaxValue);
        SelectedRoot[] roots = [.. resolved.Roots.Select(root => new SelectedRoot(root.Id, root.Kind))];
        SelectedTab[] members = [.. resolved.Members.OrderBy(tab => Place(tab.Id))
            .Select(tab => new SelectedTab(tab.Id, tab.Placement, tab.FolderId, tab.SplitGroupId))];
        var selection = new TabSelection([.. roots.Where(root => !root.Kind.OpensList).Select(root => root.Id)],
            [.. roots.Where(root => root.Kind.OpensList).Select(root => root.Id)], [.. members.Select(member => member.Id)]);
        return new(selection, roots, members, [.. resolved.Folders.OrderBy(Place)]);
    }

    #endregion
}
