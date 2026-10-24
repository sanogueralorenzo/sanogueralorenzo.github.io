using CrestCore.Contracts;

namespace CrestCore.Domain;

/// What a person does to the tabs they selected together. Each action works on
/// a detached copy of the Space's organization and checks every rule before it
/// changes anything, so a refusal leaves the Space as it was.
public sealed partial class BrowserTabCollection {
    #region Actions - Closing

    /// Archives the selected open tabs, and answers the tab the window shows
    /// next: `fallback` in place of `shown` when it went, or none. Refused with
    /// `CurrentTabsOnly` for a saved or pinned tab.
    public Guid? CloseSelected(ResolvedSelection selection, Guid? shown, Guid? fallback, DateTimeOffset now) {
        RequireSelectedTabs(selection);
        if (selection.Members.FirstOrDefault(tab => tab.Placement.IsDurable) is { } durable)
            throw new Rejected(new CurrentTabsOnly(durable.Id));
        return DismissTabs(selection.MemberIds, shown, fallback, now, deleting: false, ensureSelection: false,
            resetArchivePlacement: false);
    }

    /// Deletes the selected tabs into the archive as open tabs, and answers the
    /// tab the window shows next: `fallback` in place of `shown` when it went,
    /// or none.
    public Guid? DeleteSelected(ResolvedSelection selection, Guid? shown, Guid? fallback, DateTimeOffset now) {
        RequireSelectedTabs(selection);
        var next = DismissTabs(selection.MemberIds, shown, fallback, now, deleting: true, ensureSelection: true,
            resetArchivePlacement: true);
        return shown is { } removed && selection.Holds(removed)
            ? fallback is { } other && tabs.Any(tab => tab.Id == other) ? other : null
            : next;
    }

    #endregion

    #region Actions - Copying

    /// Copies the selected tabs to the end of the open tabs, in order, and
    /// answers each source with its copy. The copies of a split's members form
    /// a split of their own that keeps the source split's name, icon and tint.
    public IReadOnlyList<(Guid Source, Guid Copy)> DuplicateSelected(ResolvedSelection selection, IIdSource ids, DateTimeOffset now) {
        RequireSelectedTabs(selection);
        List<(Guid Source, Guid Copy)> copies = [];
        foreach (var tab in selection.Members)
            copies.Add((tab.Id, DuplicateTab(tab.Id, ids, now, requestedIndex: tabs.Count).Id));
        foreach (var group in SelectedGroups(selection)) {
            Guid[] copied = [.. selection.Members.Where(tab => tab.SplitGroupId == group)
                .Select(tab => copies.Single(pair => pair.Source == tab.Id).Copy)];
            if (copied.Length < 2) continue;
            var copiedGroup = ids.Next();
            foreach (var tab in copied.Skip(1)) JoinSplitInPlace(tab, copied[0], null, copiedGroup, now);
            CopySplitMetadata(group, copiedGroup, now);
        }
        return copies;
    }

    #endregion

    #region Actions - Splits

    /// Joins the selected tabs to the split of `target`, or of the first
    /// selected tab, at member `index` and on, and answers the last tab that
    /// joined, or `shown` when none had to, with the copies made for saved or
    /// pinned tabs. A split copied into new tabs keeps its name, icon and tint.
    /// Refused with `WebPagesOnly` for a Start Page target, and
    /// `SplitNeedsTwoTabs` or `SplitLimitReached` for a split that would be
    /// too small or too large.
    public (Guid? Shown, IReadOnlyList<(Guid Source, Guid Copy)> Copies) SplitSelected(ResolvedSelection selection, Guid? target,
        int? index, Guid? shown, IIdSource ids, DateTimeOffset now) {
        RequireSelectedTabs(selection);
        var targetId = target ?? selection.MemberIds[0];
        if (Tab(targetId).Content.IsStartPage) throw new Rejected(new WebPagesOnly(targetId));
        var existing = SplitMembers(targetId).Select(tab => tab.Id).ToHashSet();
        int size = existing.Union(selection.MemberIds).Count();
        if (size < 2) throw new Rejected(new SplitNeedsTwoTabs(MaximumSplitMembers));
        if (size > MaximumSplitMembers) throw new Rejected(new SplitLimitReached(MaximumSplitMembers));
        List<(Guid Source, Guid Copy)> copies = [];
        List<(Guid Source, Guid Copy)> groupCopies = [];
        var insertion = index;
        foreach (var id in selection.MemberIds.Where(id => !existing.Contains(id))) {
            var group = Tab(targetId).SplitGroupId;
            var joined = JoinSplit(id, targetId, insertion, ids, now);
            copies.AddRange(joined.Copies);
            shown = joined.SelectedTab;
            var targetCopy = joined.Copies.FirstOrDefault(pair => pair.Source == targetId);
            if (targetCopy != default) {
                targetId = targetCopy.Copy;
                if (group is { } copiedFrom) groupCopies.Add((copiedFrom, Tab(targetId).SplitGroupId!.Value));
            }
            if (insertion is { } slot) insertion = checked(slot + 1);
        }
        foreach (var (source, copy) in groupCopies) CopySplitMetadata(source, copy, now);
        return (shown, copies);
    }

    /// Dissolves every split the selected tabs belong to.
    public void SeparateSelected(ResolvedSelection selection, DateTimeOffset now) {
        RequireSelectedTabs(selection);
        foreach (var group in SelectedGroups(selection)) DissolveSplit(group, now);
    }

    #endregion

    #region Actions - Residency

    /// Keeps the selected tabs' pages loaded while they are not shown, or lets
    /// them unload. A selected folder's tabs are included. Refused with
    /// `WebPagesOnly` for a tab that shows no web page.
    public void KeepSelectedLoaded(ResolvedSelection selection, bool keeps) {
        RequireWholeSplits(selection);
        if (selection.Members.FirstOrDefault(tab => !tab.Content.IsWebPage) is { } other) throw new Rejected(new WebPagesOnly(other.Id));
        foreach (var tab in selection.Members) tab.SetResidency(keeps);
    }

    #endregion

    #region Actions - Moving

    /// Moves the selected tabs into `destination`, another Space's
    /// organization, each to the end of its own section there, and answers the
    /// tab each Space's window shows next. The window gives up `shown` for
    /// `fallback` when it moved; when `follows`, the destination shows the
    /// shown tab if it moved, or else the first moved tab. Refused with
    /// `CannotMoveSplitAcrossSpaces` for a split member and `PinnedTabsFull`
    /// when the destination cannot hold them all.
    public (Guid? Shown, Guid? DestinationShown) MoveSelected(ResolvedSelection selection, BrowserTabCollection destination, Guid? shown,
        Guid? fallback, Guid? destinationShown, bool follows, DateTimeOffset now) {
        ArgumentNullException.ThrowIfNull(destination);
        RequireSelectedTabs(selection);
        if (selection.Members.FirstOrDefault(tab => tab.SplitGroupId is not null) is { } member)
            throw new Rejected(new CannotMoveSplitAcrossSpaces(member.Id));
        foreach (var placement in TabPlacement.All)
            RequireRoom(placement, destination.tabs.Count(tab => tab.Placement == placement)
                + selection.Members.Count(tab => tab.Placement == placement));
        var followed = shown is { } active && selection.Holds(active) ? active : selection.MemberIds[0];
        foreach (var id in selection.MemberIds)
            shown = TransferTo(destination, id, shown, fallback, null, null, null, afterSelection: false, destinationShown, now);
        if (!follows) return (shown, destinationShown);
        destination.Tab(followed).Activate(now);
        return (shown, followed);
    }

    #endregion

    #region Actions - Filing

    /// Moves the selection into `folder` or to the top level of `placement`'s
    /// section, before the tab `before` or the folder `beforeFolder`, in
    /// order: a selected folder moves whole, and a split member brings its
    /// split along unless `leavesSplits`. In a section that holds no folders
    /// the tabs move one by one, refused with `CannotPinSplit` for a member
    /// that stays in its split and `PinnedTabsFull` for a full section.
    public void FileSelected(ResolvedSelection selection, TabPlacement placement, Guid? folder, Guid? before, Guid? beforeFolder,
        bool leavesSplits, DateTimeOffset now) {
        ArgumentNullException.ThrowIfNull(selection);
        ArgumentNullException.ThrowIfNull(placement);
        if (selection.HoldsFolders) {
            FileRoots(selection, placement, folder, before, beforeFolder, leavesSplits, now);
            return;
        }
        if (before is { } anchor && selection.Holds(anchor)) throw new Rejected(new InvalidFolderPlacement());
        if (placement.HoldsFolders) {
            var moving = SplitRuns(selection.MemberIds, leavesSplits);
            OrderSelected(moving);
            FileTabs(moving, placement, folder, now, before, beforeFolder, leavesSplits);
            return;
        }
        if (!placement.HoldsSplits && !leavesSplits && selection.Members.FirstOrDefault(tab => tab.SplitGroupId is not null) is { } member)
            throw new Rejected(new CannotPinSplit(member.Id));
        RequireRoom(placement, tabs.Count(tab => tab.Placement == placement && !selection.Holds(tab.Id)) + selection.Members.Count);
        if (folder is not null || beforeFolder is not null
            || before is { } named && !tabs.Any(tab => tab.Id == named && tab.Placement == placement))
            throw new Rejected(new InvalidFolderPlacement());
        foreach (var id in selection.MemberIds) MoveTab(id, placement, null, before, leavesSplits, now);
    }

    /// Makes a folder named `title` in `color` at the top level of
    /// `placement`'s section, with an identity from `ids`, and moves the
    /// selection into it: a selected folder moves in whole.
    public Guid FolderSelected(ResolvedSelection selection, TabPlacement placement, string title, BrandColor color, IIdSource ids,
        DateTimeOffset now) {
        RequireWholeSplits(selection);
        if (selection.HoldsFolders) {
            var made = MakeFolder(placement, title, color, ids);
            FileRoots(selection, placement, made, null, null, leavesSplits: false, now);
            return made;
        }
        OrderSelected(selection.MemberIds);
        var folder = MakeFolder(placement, title, color, ids);
        FileTabs(selection.MemberIds, placement, folder, now);
        return folder;
    }

    /// Makes an open-tabs folder named `title` in `color` in the place of the
    /// open tab `tabId`, with an identity from `ids`, and moves that tab and
    /// then the selection into it. Refused with `InvalidFolderPlacement` when
    /// the tab is saved or pinned, in a folder or a split, a Start Page, or
    /// selected.
    public Guid FolderSelectedAround(ResolvedSelection selection, Guid tabId, string title, BrandColor color, IIdSource ids,
        DateTimeOffset now) {
        RequireSelectedTabs(selection);
        if (selection.Holds(tabId)) throw new Rejected(new InvalidFolderPlacement());
        var target = Tab(tabId);
        if (target.Placement.IsDurable || target.FolderId is not null || target.SplitGroupId is not null || target.Content.IsStartPage)
            throw new Rejected(new InvalidFolderPlacement());
        Guid[] wrapped = [target.Id, .. selection.MemberIds];
        OrderSelected(wrapped);
        var folder = MakeFolder(TabPlacement.Current, title, color, ids);
        FileTabs(wrapped, TabPlacement.Current, folder, now);
        return folder;
    }

    /// Moves each selected root into `folder` or to the top level of
    /// `placement`'s section, the roots one block after another in order,
    /// before the tab `before` or the folder `beforeFolder`. A folder block is
    /// the folder with everything in it; a tab block is the tab with its split
    /// unless `leavesSplits`. Refused with `InvalidFolderPlacement` for a
    /// section without folders or an anchor that moves with the selection or
    /// sits elsewhere, and `FolderCycle` for a destination folder the
    /// selection holds.
    private void FileRoots(ResolvedSelection selection, TabPlacement placement, Guid? folder, Guid? before, Guid? beforeFolder,
        bool leavesSplits, DateTimeOffset now) {
        if (folder is { } parent && selection.Folders.Contains(parent)) throw new Rejected(new FolderCycle(parent));
        if (!placement.HoldsFolders || before is { } tab && selection.Holds(tab)
            || beforeFolder is { } sibling && selection.Folders.Contains(sibling))
            throw new Rejected(new InvalidFolderPlacement());
        if (folder is { } owner && KnownFolder(owner).Location != placement
            || beforeFolder is { } next && (KnownFolder(next).ParentId != folder || KnownFolder(next).Location != placement)
            || beforeFolder is null && before is { } anchor && (Tab(anchor).FolderId != folder || Tab(anchor).Placement != placement
                || SplitMembers(anchor)[0].Id != anchor))
            throw new Rejected(new InvalidFolderPlacement());
        List<(ResolvedSelection.Root Root, Guid[] Tabs)> blocks = [];
        HashSet<Guid> included = [];
        foreach (var root in selection.Roots) {
            if (root.IsFolder) blocks.Add((root, []));
            else if (!included.Contains(root.Id)) {
                var members = SplitRuns([root.Id], leavesSplits);
                included.UnionWith(members);
                blocks.Add((root, members));
            }
        }
        var tabAnchor = before;
        var folderAnchor = beforeFolder;
        foreach (var block in blocks.AsEnumerable().Reverse()) {
            if (block.Root.IsFolder) {
                MoveFolder(block.Root.Id, placement, folder, now, folderAnchor, tabAnchor);
                folderAnchor = block.Root.Id;
                tabAnchor = null;
            } else {
                FileTabs(block.Tabs, placement, folder, now, tabAnchor, folderAnchor, leavesSplits);
                tabAnchor = block.Tabs[0];
                folderAnchor = null;
            }
        }
    }

    /// A new folder at the top level of `placement`'s section.
    private Guid MakeFolder(TabPlacement placement, string title, BrandColor color, IIdSource ids) {
        var folder = ids.Next();
        AddFolder(folder, title, placement);
        SetFolderColor(folder, color);
        return folder;
    }

    /// Gathers the tabs `requested` names where the first of them is, in that order.
    private void OrderSelected(IReadOnlyList<Guid> requested) {
        BrowserTab[] members = [.. requested.Select(Tab)];
        var ids = requested.ToHashSet();
        int insertion = tabs.FindIndex(tab => ids.Contains(tab.Id));
        tabs.RemoveAll(tab => ids.Contains(tab.Id));
        tabs.InsertRange(insertion, members);
    }

    /// The tabs `requested` names, each with its whole split run unless
    /// `leavesSplits`, in order and once each.
    private Guid[] SplitRuns(IReadOnlyList<Guid> requested, bool leavesSplits) =>
        leavesSplits ? [.. requested] : [.. requested.SelectMany(id => SplitMembers(id).Select(tab => tab.Id)).Distinct()];

    #endregion

    #region Actions - Rules

    /// Refuses a selection holding folders, for an action on tabs alone, and
    /// one holding part of a split.
    private void RequireSelectedTabs(ResolvedSelection selection) {
        RequireWholeSplits(selection);
        if (selection.HoldsFolders) throw new Rejected(new SelectionHoldsFolders());
    }

    /// Refuses a selection holding some members of a split and not the rest.
    private void RequireWholeSplits(ResolvedSelection selection) {
        ArgumentNullException.ThrowIfNull(selection);
        foreach (var tab in selection.Members)
            if (tab.SplitGroupId is { } group && SplitMembers(tab.Id).Any(member => !selection.Holds(member.Id)))
                throw new Rejected(new IncompleteSplit(group));
    }

    /// The splits the selected tabs belong to, in the order they come.
    private static IReadOnlyList<Guid> SelectedGroups(ResolvedSelection selection) =>
        [.. selection.Members.Select(tab => tab.SplitGroupId).OfType<Guid>().Distinct()];

    #endregion
}
