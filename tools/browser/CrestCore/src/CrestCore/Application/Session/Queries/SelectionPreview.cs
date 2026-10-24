using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// What the tabs and folders a person picked in a Space's sidebar hold, as a
/// window shows it before it acts on them: the picks no picked folder holds, in
/// sidebar order, and every tab and folder they hold. A pick the Space does not
/// hold, and a Start Page, which the sidebar lists nowhere, are left out. A
/// preview reads a locked Space as a person sees it; only an action refuses it.
public sealed record SelectionPreview(Guid WorkspaceId, Guid SpaceId, IReadOnlyList<Guid> TabIds, IReadOnlyList<Guid> FolderIds)
    : Query<SelectedTabs> {
    #region Actions - Answering

    internal override SelectedTabs Answer(CrestApp app) => Answer(app.Device.Workspace(WorkspaceId));

    /// What the picks `preview` names hold in its Space, as a window shows it
    /// before it acts on them. A locked Space is read as a person sees it.
    private SelectedTabs Answer(NativeSessionAuthority workspace) {
        SpaceState space;
        lock (NativeSessionAuthority.Gate) space = workspace.AcceptedSession.Spaces.FirstOrDefault(candidate => candidate.Id == SpaceId)
            ?? throw new Rejected(new UnknownSpace(SpaceId));
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
