using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection {
    #region Actions - Selection

    /// `selection` resolved in this Space: a picked tab or folder inside a
    /// picked folder goes with that folder, and the rest are ordered as the
    /// sidebar lists them. Refused with `SelectionChanged` when it picks
    /// nothing, picks one tab or folder twice or one the Space does not hold,
    /// holds a Start Page, or holds other tabs than the window saw.
    public ResolvedSelection Select(TabSelection selection) {
        ArgumentNullException.ThrowIfNull(selection);
        IReadOnlyList<Guid> picked = [.. selection.TabIds, .. selection.FolderIds];
        if (picked.Count == 0 || picked.Distinct().Count() != picked.Count
            || selection.FolderIds.Any(id => folders.All(folder => folder.Id != id))
            || selection.TabIds.Any(id => tabs.All(tab => tab.Id != id)))
            throw new Rejected(new SelectionChanged());
        var resolved = Resolve(selection.TabIds, selection.FolderIds);
        var seen = selection.MemberTabIds.ToHashSet();
        if (resolved.Members.Any(tab => tab.Content.IsStartPage) || seen.Count != selection.MemberTabIds.Count
            || resolved.Members.Count != seen.Count || !resolved.Members.All(tab => seen.Contains(tab.Id)))
            throw new Rejected(new SelectionChanged());
        return resolved;
    }

    /// What picking `tabIds` and `folderIds` in this Space's sidebar holds, as
    /// a window previews it before it acts: a pick the Space does not hold, a
    /// pick made twice and a Start Page are left out, and so are the Start
    /// Pages a picked folder holds.
    public ResolvedSelection Preview(IReadOnlyList<Guid> tabIds, IReadOnlyList<Guid> folderIds) {
        ArgumentNullException.ThrowIfNull(tabIds);
        ArgumentNullException.ThrowIfNull(folderIds);
        var resolved = Resolve([.. tabIds.Distinct().Where(id => tabs.Any(tab => tab.Id == id && !tab.Content.IsStartPage))],
            [.. folderIds.Distinct().Where(id => folders.Any(folder => folder.Id == id))]);
        return new(resolved.Roots, resolved.Folders, [.. resolved.Members.Where(tab => !tab.Content.IsStartPage)]);
    }

    /// Picks this Space holds, each once, resolved: a picked tab or folder
    /// inside a picked folder goes with that folder, the rest in sidebar
    /// order, each folder root followed by every tab of its subtree.
    private ResolvedSelection Resolve(IReadOnlyList<Guid> tabIds, IReadOnlyList<Guid> folderIds) {
        var tree = new FolderTree(folders);
        var subtrees = folderIds.ToDictionary(id => id, tree.Subtree);
        var covered = subtrees.SelectMany(entry => entry.Value.Where(id => id != entry.Key)).ToHashSet();
        var held = subtrees.Values.SelectMany(subtree => subtree).ToHashSet();
        var positions = SidebarPositions();
        ResolvedSelection.Root[] roots = [
            .. folderIds.Where(id => !covered.Contains(id)).Select(id => new ResolvedSelection.Root(id, SidebarRowKind.Folder)),
            .. tabIds.Where(id => Tab(id).FolderId is not { } folder || !held.Contains(folder))
                .Select(id => new ResolvedSelection.Root(id, SidebarRowKind.Tab))
        ];
        roots = [.. roots.OrderBy(root => positions.GetValueOrDefault(root.Id, int.MaxValue))];
        BrowserTab[] members = [.. roots.SelectMany(root => root.IsFolder
            ? tabs.Where(tab => tab.FolderId is { } folder && subtrees[root.Id].Contains(folder))
            : [Tab(root.Id)])];
        return new(roots, held, members);
    }

    /// Where each tab and folder falls in the list the Space's sidebar shows,
    /// counting from zero, as its outline orders them. Start Pages, which the
    /// sidebar does not list, have no place.
    private Dictionary<Guid, int> SidebarPositions() => SidebarOutline.Of(TabStates, folders).Positions();

    #endregion
}
