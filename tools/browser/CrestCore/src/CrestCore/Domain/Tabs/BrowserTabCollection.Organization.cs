using System.Text;

using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection {
    #region Variables

    private const int MaximumFolderSymbolBytes = 128;
    private const string UntitledFolderName = "Untitled Folder";

    #endregion

    #region Actions - Organization

    public void AddFolder(Guid id, string name, TabPlacement? location = null, Guid? parent = null) {
        var tree = new FolderTree(folders);
        if (folders.Count >= FolderTree.MaximumCount) throw new Rejected(new FolderLimitReached(FolderTree.MaximumCount));
        if (folders.Any(f => f.Id == id)) throw new Rejected(new FolderAlreadyExists(id));
        location ??= TabPlacement.Saved;
        if (!location.HoldsFolders) throw new Rejected(new InvalidFolderPlacement());
        int insertion = folders.Count;
        if (parent is { } p) {
            location = KnownFolder(p).Location;
            if (tree.Depth(p) + 1 >= FolderTree.MaximumDepth) throw new Rejected(new FolderDepthLimitReached(FolderTree.MaximumDepth));
            var subtree = tree.Subtree(p); insertion = folders.FindLastIndex(f => subtree.Contains(f.Id)) + 1;
        }
        folders.Insert(insertion, new(id, location, FolderName(name), ParentId: parent));
    }

    public void RenameFolder(Guid id, string name) {
        var folder = KnownFolder(id);
        folders[folders.IndexOf(folder)] = folder with { Title = FolderName(name) };
    }

    public void CollapseFolder(Guid id, bool collapsed, DateTimeOffset now) {
        var folder = KnownFolder(id);
        if (folder.IsCollapsed == collapsed) return;
        folders[folders.IndexOf(folder)] = folder with { IsCollapsed = collapsed, CollapseModifiedAt = now };
    }

    /// Whether the folder's color changed.
    public bool SetFolderColor(Guid id, BrandColor color) {
        var folder = KnownFolder(id);
        if (folder.Color == color) return false;
        folders[folders.IndexOf(folder)] = folder with { Color = color };
        return true;
    }

    /// Whether the folder's symbol changed. A symbol is an SF Symbol name or an
    /// emoji spelling, and never empty or longer than 128 UTF-8 bytes.
    public bool SetFolderSymbol(Guid id, string symbol) {
        var folder = KnownFolder(id);
        if (symbol.Length == 0 || Encoding.UTF8.GetByteCount(symbol) > MaximumFolderSymbolBytes)
            throw new Rejected(new InvalidFolderSymbol(MaximumFolderSymbolBytes));
        if (folder.Symbol == symbol) return false;
        folders[folders.IndexOf(folder)] = folder with { Symbol = symbol };
        return true;
    }

    public void DeleteFolder(Guid id, DateTimeOffset now) {
        var folder = KnownFolder(id);
        var next = folders.Where(f => f.Id != id).Select(f => f.ParentId == id ? f with { ParentId = folder.ParentId } : f).ToArray();
        var ordered = new FolderTree(next).DisplayOrder();
        foreach (var tab in tabs.Where(t => t.FolderId == id))
            tab.Place(tab.Placement, folder.ParentId, now, preservesSplit: true);
        folders.Clear(); folders.AddRange(ordered);
    }

    private static void ValidateInsertion(IReadOnlyList<BrowserTab> remaining, int insertion) {
        if (insertion > 0 && insertion < remaining.Count && remaining[insertion].SplitGroupId is { } split
            && remaining[insertion - 1].SplitGroupId == split) throw new Rejected(new SplitBoundary());
    }

    private static int SectionEnd(List<BrowserTab> remaining, TabPlacement location) {
        int last = remaining.FindLastIndex(t => t.Placement == location);
        return last >= 0 ? last + 1 : NextSection(remaining, location);
    }

    internal void NormalizeSplits(DateTimeOffset now) {
        RepairSplitMembership();
        foreach (var group in tabs.Where(t => t.SplitGroupId is not null).GroupBy(t => t.SplitGroupId))
            if (group.Count() < 2) foreach (var tab in group) { tab.SetSplit(null); tab.MarkPosition(now); }
    }

    public void FileTabs(IReadOnlyCollection<Guid> requested, TabPlacement location, Guid? folder,
        DateTimeOffset now, Guid? before = null, Guid? beforeFolder = null, bool detachSplitMembers = false) {
        if (requested.Count == 0 || !location.HoldsFolders) throw new Rejected(new InvalidFolderPlacement());
        foreach (var id in requested) _ = Tab(id);
        var tree = new FolderTree(folders);
        if (folder is { } parent && KnownFolder(parent).Location != location) throw new Rejected(new InvalidFolderPlacement());
        if (beforeFolder is { } sibling && (KnownFolder(sibling).ParentId != folder || KnownFolder(sibling).Location != location))
            throw new Rejected(new InvalidFolderPlacement());
        var selected = requested.ToHashSet();
        var splits = detachSplitMembers ? [] : tabs.Where(t => selected.Contains(t.Id) && t.SplitGroupId is not null)
            .Select(t => t.SplitGroupId!.Value).ToHashSet();
        var members = tabs.Where(t => selected.Contains(t.Id) || t.SplitGroupId is { } s && splits.Contains(s)).ToArray();
        var memberIds = members.Select(t => t.Id).ToHashSet();
        var remaining = tabs.Where(t => !memberIds.Contains(t.Id)).ToList();
        var nextFolders = tree.PreserveOrder(memberIds, tabs);
        var remainingTree = new FolderTree(nextFolders);
        var anchor = beforeFolder is { } target ? remainingTree.TabAnchor(target, remaining) : before;
        if (anchor is { } a && (memberIds.Contains(a) || !remaining.Any(t => t.Id == a && t.Placement == location)))
            throw new Rejected(new InvalidFolderPlacement());
        var predecessors = remainingTree.EmptyPredecessors(beforeFolder, anchor, folder, location, remaining);
        int insertion;
        if (anchor is { } actual) insertion = remaining.FindIndex(t => t.Id == actual);
        else if (folder is not null && remaining.FindLastIndex(t => t.FolderId == folder) is var last && last >= 0) insertion = last + 1;
        else insertion = folder is null ? SectionEnd(remaining, location) : Math.Min(tabs.FindIndex(t => memberIds.Contains(t.Id)), remaining.Count);
        if (detachSplitMembers && anchor is null && insertion > 0 && insertion < remaining.Count
            && remaining[insertion].SplitGroupId is { } crossing && remaining[insertion - 1].SplitGroupId == crossing)
            while (insertion < remaining.Count && remaining[insertion].SplitGroupId == crossing) insertion++;
        ValidateInsertion(remaining, insertion);
        nextFolders = nextFolders.Select(f => predecessors.Contains(f.Id) ? f with { OrderAnchorTabId = members[0].Id } : f).ToList();
        // No mutation before all topology and split-boundary checks have passed.
        foreach (var tab in members) {
            tab.Place(location, folder, now, preservesSplit: !detachSplitMembers);
            if (detachSplitMembers) tab.SetSplit(null);
            tab.MarkPosition(now);
        }
        remaining.InsertRange(insertion, members);
        tabs.Clear(); tabs.AddRange(remaining); folders.Clear(); folders.AddRange(nextFolders);
        if (detachSplitMembers) NormalizeSplits(now);
    }

    public void MoveFolder(Guid id, TabPlacement? location, Guid? parent, DateTimeOffset now,
        Guid? beforeFolder = null, Guid? beforeTab = null) {
        var tree = new FolderTree(folders); var source = KnownFolder(id);
        if (parent is { } named) _ = KnownFolder(named);
        var movingIds = tree.Subtree(id);
        if (parent is { } p && movingIds.Contains(p)) throw new Rejected(new FolderCycle(id));
        int destinationDepth = parent is { } parentId ? tree.Depth(parentId) + 1 : 0;
        if (destinationDepth + movingIds.Max(tree.Depth) - tree.Depth(id) >= FolderTree.MaximumDepth)
            throw new Rejected(new FolderDepthLimitReached(FolderTree.MaximumDepth));
        var destination = parent is { } owner ? tree.Folder(owner).Location : location ?? source.Location;
        if (!destination.HoldsFolders) throw new Rejected(new InvalidFolderPlacement());
        if (beforeFolder is { } sibling && (movingIds.Contains(sibling) || KnownFolder(sibling).ParentId != parent
            || KnownFolder(sibling).Location != destination)) throw new Rejected(new InvalidFolderPlacement());
        var members = tabs.Where(t => t.FolderId is { } f && movingIds.Contains(f)).ToArray();
        var memberIds = members.Select(t => t.Id).ToHashSet();
        if (beforeTab is { } a && (memberIds.Contains(a) || !tabs.Any(t => t.Id == a && t.Placement == destination)))
            throw new Rejected(new InvalidFolderPlacement());
        var nextFolders = tree.PreserveOrder(memberIds, tabs, movingIds);
        var remaining = tabs.Where(t => !memberIds.Contains(t.Id)).ToList();
        var remainingTree = new FolderTree(nextFolders);
        var anchor = beforeFolder is { } target ? remainingTree.TabAnchor(target, remaining) : beforeTab;
        var predecessors = remainingTree.EmptyPredecessors(beforeFolder, anchor, parent, destination, remaining);
        var moving = nextFolders.Where(f => movingIds.Contains(f.Id)).Select(f => f with { Location = destination, ParentId = f.Id == id ? parent : f.ParentId, OrderAnchorTabId = f.Id == id ? anchor : f.OrderAnchorTabId }).ToArray();
        nextFolders.RemoveAll(f => movingIds.Contains(f.Id));
        int folderInsertion = beforeFolder is { } bf ? nextFolders.FindIndex(f => f.Id == bf)
            : parent is { } parentFolder ? nextFolders.FindLastIndex(f => tree.Subtree(parentFolder).Contains(f.Id)) + 1 : nextFolders.Count;
        nextFolders.InsertRange(folderInsertion, moving);
        nextFolders = new FolderTree(nextFolders).DisplayOrder().ToList();
        int insertion;
        if (anchor is { } actual && remaining.FindIndex(t => t.Id == actual) is var at && at >= 0) insertion = at;
        else if (parent is { } targetParent && remaining.FindLastIndex(t => t.FolderId is { } f && tree.Subtree(targetParent).Contains(f)) is var last && last >= 0)
            insertion = last + 1;
        else insertion = SectionEnd(remaining, destination);
        ValidateInsertion(remaining, insertion);
        foreach (var tab in members) { tab.Place(destination, tab.FolderId, now, preservesSplit: true); tab.MarkPosition(now); }
        remaining.InsertRange(insertion, members);
        if (members.Length > 0) nextFolders = nextFolders.Select(f => predecessors.Contains(f.Id) && !movingIds.Contains(f.Id)
            ? f with { OrderAnchorTabId = members[0].Id } : f).ToList();
        tabs.Clear(); tabs.AddRange(remaining); folders.Clear(); folders.AddRange(nextFolders);
    }

    #endregion

    #region Mutators

    /// A folder's name: its trimmed title, or "Untitled Folder" for a blank one.
    private static string FolderName(string name) {
        var trimmed = name.Trim();
        if (trimmed.Length > BrowserTabCollection.MaximumNameLength) throw new Rejected(new InvalidName(BrowserTabCollection.MaximumNameLength));
        return trimmed.Length == 0 ? UntitledFolderName : trimmed;
    }

    #endregion
}
