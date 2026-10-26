using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Synchronous value edits used by native hosts that still own page lifetimes.
/// No engine calls or page creation take place while an edit is evaluated.
public sealed partial class BrowserTabCollection {
    #region Actions - Editing

    /// Moves a tab into `folder`, or to the top level of `placement`'s section,
    /// before `before` when it is there, or after the section's last tab.
    /// Answers whether anything moved. Refused with `UnknownFolder` or
    /// `InvalidFolderPlacement` for a folder that is not there or not in the
    /// section, or a tab named to go before itself, and with `PinnedTabsFull`
    /// for a full section.
    public bool MoveTab(Guid id, TabPlacement placement, Guid? folder, Guid? before,
        bool detachSplit, DateTimeOffset now) {
        var tab = Tab(id);
        if (before == id) throw new Rejected(new InvalidFolderPlacement());
        if (folder is { } named && (KnownFolder(named).Location != placement || !placement.HoldsFolders))
            throw new Rejected(new InvalidFolderPlacement());
        var remaining = tabs.Where(t => t.Id != id).ToList();
        RequireRoom(placement, remaining.Count(t => t.Placement == placement) + 1);
        bool Matches(BrowserTab tab) => tab.Placement == placement && tab.FolderId == folder;
        int insertion = before is { } target ? remaining.FindIndex(t => t.Id == target && Matches(t)) : -1;
        if (insertion < 0) {
            int last = remaining.FindLastIndex(t => Matches(t));
            insertion = last >= 0 ? last + 1 : NextSection(remaining, placement);
        }
        if (tabs.IndexOf(tab) == insertion && tab.Placement == placement && tab.FolderId == folder
            && (!detachSplit || tab.SplitGroupId is null)) return false;
        var nextFolders = new FolderTree(folders).PreserveOrder([id], tabs);
        tab.Place(placement, folder, now, preservesSplit: !detachSplit);
        if (detachSplit) tab.SetSplit(null);
        tab.MarkPosition(now); remaining.Insert(insertion, tab);
        tabs.Clear(); tabs.AddRange(remaining); folders.Clear(); folders.AddRange(nextFolders);
        RepairSplitMembership();
        if (detachSplit) NormalizeSplits(now);
        return true;
    }

    /// Joins the tab to the split of `targetId`, or to a new split `newGroup`
    /// with it, at member `memberIndex`. Refused with `AlreadyInSplit` for a
    /// tab named to join itself, `CannotPinSplit` for a target whose section
    /// holds no splits, and `SplitLimitReached` for a full split.
    public bool JoinSplitInPlace(Guid id, Guid targetId, int? memberIndex, Guid newGroup, DateTimeOffset now) {
        if (id == targetId) throw new Rejected(new AlreadyInSplit(id));
        var tab = Tab(id); var target = Tab(targetId);
        if (!target.Placement.HoldsSplits) throw new Rejected(new CannotPinSplit(targetId));
        var run = SplitMembers(targetId);
        var members = run.Where(t => t.Id != id).ToArray();
        if (members.Length >= MaximumSplitMembers) throw new Rejected(new SplitLimitReached(MaximumSplitMembers));
        int slot = Math.Clamp(memberIndex ?? members.Length, 0, members.Length);
        Guid? anchor = slot < members.Length ? members[slot].Id
            : tabs.Skip(tabs.IndexOf(run[^1]) + 1).FirstOrDefault(t => t.Id != id)?.Id;
        var group = target.SplitGroupId ?? newGroup;
        MoveTab(id, target.Placement, target.FolderId, anchor,
            tab.SplitGroupId is not null && tab.SplitGroupId != target.SplitGroupId, now);
        foreach (var member in members.Append(tab)) { member.SetSplit(group); member.MarkPosition(now); }
        NormalizeSplits(now);
        return true;
    }

    public bool MoveSplitMember(Guid id, int memberIndex, DateTimeOffset now) {
        var tab = Tab(id); var run = SplitMembers(id);
        if (run.Count < 2) return false;
        int first = tabs.IndexOf(run[0]); int insertion = first + Math.Clamp(memberIndex, 0, run.Count - 1);
        if (tabs.IndexOf(tab) == insertion) return false;
        var originalPositions = run.ToDictionary(t => t.Id, tabs.IndexOf);
        tabs.Remove(tab); tabs.Insert(insertion, tab);
        foreach (var member in run)
            if (tabs.IndexOf(member) != originalPositions[member.Id]) member.MarkPosition(now);
        return true;
    }

    /// Where a tab opened from `origin` goes: directly after it, or after its
    /// whole split when it is in one, so a new tab never lands inside a split.
    /// Null when `origin` is not in this Space, which leaves placement to the
    /// tab's section.
    public int? InsertionIndexAfter(Guid origin) =>
        tabs.Any(t => t.Id == origin) ? tabs.IndexOf(SplitMembers(origin)[^1]) + 1 : null;

    /// Adds a tab to its section, at `requestedIndex` within it, or where its
    /// section puts a new tab. Refused with `PinnedTabsFull`,
    /// `TabLimitReached` or `TabAlreadyExists`.
    public void InsertTab(BrowserTab tab, int? requestedIndex, bool duplicate = false) {
        RequireRoom(tab.Placement, tabs.Count(t => t.Placement == tab.Placement) + 1);
        if (tabs.Count >= MaximumTabs) throw new Rejected(new TabLimitReached(MaximumTabs));
        if (tabs.Any(t => t.Id == tab.Id)) throw new Rejected(new TabAlreadyExists(tab.Id));
        int lower = tabs.FindIndex(t => t.Placement.Rank >= tab.Placement.Rank);
        if (lower < 0) lower = tabs.Count;
        int upper = NextSection(tabs, tab.Placement);
        int insertion = requestedIndex is { } requested ? Math.Clamp(requested, lower, upper)
            : duplicate || !tab.Placement.IsDurable ? lower : upper;
        tabs.Insert(insertion, tab);
    }

    /// Archives the `requested` tabs and answers the tab the Space shows next.
    /// Refused with `UnknownTab` for a tab the Space does not hold, and with
    /// `CurrentTabsOnly` for a saved or pinned tab unless `deleting`.
    public Guid? DismissTabs(IReadOnlyCollection<Guid> requested, Guid? selected, Guid? fallback,
        DateTimeOffset now, bool deleting, bool ensureSelection, bool resetArchivePlacement) {
        var removing = requested.ToHashSet();
        foreach (var id in removing) _ = Tab(id);
        var removed = tabs.Where(t => removing.Contains(t.Id)).ToArray();
        if (!deleting && removed.FirstOrDefault(t => t.Placement.IsDurable) is { } durable)
            throw new Rejected(new CurrentTabsOnly(durable.Id));
        var orderedFolders = new FolderTree(folders).PreserveOrder(removing, tabs);
        foreach (var tab in removed.Where(t => !t.Content.IsStartPage)) {
            var value = tab.State with { SplitGroupId = null };
            if (resetArchivePlacement) value = value with { Placement = TabPlacement.Current, FolderId = null, SavedUrl = null };
            archive.Add(new(value, now, deleting ? ArchiveReason.Deleted : ArchiveReason.Closed));
        }
        tabs.RemoveAll(t => removing.Contains(t.Id));
        folders.Clear(); folders.AddRange(orderedFolders);
        if (selected is { } current && removing.Contains(current))
            selected = fallback is { } candidate && tabs.Any(t => t.Id == candidate) ? candidate : null;
        if (ensureSelection && (selected is null || !tabs.Any(t => t.Id == selected)))
            selected = FallbackSelection();
        NormalizeSplits(now);
        return selected;
    }

    /// Refuses a section that cannot hold `count` tabs.
    private static void RequireRoom(TabPlacement placement, int count) {
        if (!placement.Holds(count) && placement.Capacity is { } capacity) throw new Rejected(new PinnedTabsFull(capacity));
    }

    #endregion
}
