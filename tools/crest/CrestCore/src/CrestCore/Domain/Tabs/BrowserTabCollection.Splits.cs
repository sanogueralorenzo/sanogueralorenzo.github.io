using CrestCore.Contracts;

namespace CrestCore.Domain;

public sealed partial class BrowserTabCollection {
    #region Variables

    public const int MaximumSplitMembers = 4;

    #endregion

    #region Actions - Splits

    private BrowserTab CopyTab(BrowserTab source, Guid id, DateTimeOffset now) => BrowserTab.Restore(source.State with {
        Id = id,
        Placement = TabPlacement.Current,
        FolderId = null,
        SplitGroupId = null,
        SavedUrl = null,
        LastActivatedAt = now,
        PositionModifiedAt = BrowserEditTimestamp.Normalize(now),
        TitleModifiedAt = source.CustomTitle is null ? null : BrowserEditTimestamp.Normalize(now),
        KeepsPageLoaded = false
    });

    public BrowserTab DuplicateTab(Guid sourceId, IIdSource ids, DateTimeOffset now,
        TabPlacement? placement = null, int? requestedIndex = null) {
        var source = Tab(sourceId);
        if (tabs.Count >= MaximumTabs) throw new Rejected(new TabLimitReached(MaximumTabs));
        var copy = CopyTab(source, ids.Next(), now);
        copy.Place(placement ?? TabPlacement.Current, null, now);
        InsertTab(copy, requestedIndex, duplicate: true);
        return copy;
    }

    // Saved and pinned tabs remain durable shortcuts. Joining them creates
    // current copies; the entire join is validated before changing either run.
    public SplitJoin JoinSplit(Guid sourceId, Guid targetId, int? memberIndex, IIdSource ids, DateTimeOffset now) {
        var source = Tab(sourceId); var target = Tab(targetId);
        if (sourceId == targetId) throw new Rejected(new AlreadyInSplit(sourceId));
        if (source.Content.IsStartPage || target.Content.IsStartPage)
            throw new Rejected(new WebPagesOnly(source.Content.IsStartPage ? sourceId : targetId));
        var targetMembers = SplitMembers(targetId);
        bool sameGroup = targetMembers.Any(t => t.Id == sourceId);
        if (sameGroup && memberIndex is null) throw new Rejected(new AlreadyInSplit(sourceId));
        if (!sameGroup && targetMembers.Count >= MaximumSplitMembers) throw new Rejected(new SplitLimitReached(MaximumSplitMembers));
        bool copyTarget = target.Placement.IsDurable && !sameGroup;
        bool copySource = source.Placement.IsDurable && !sameGroup;
        int copyCount = (copyTarget ? targetMembers.Count : 0) + (copySource ? 1 : 0);
        if (tabs.Count + copyCount > MaximumTabs) throw new Rejected(new TabLimitReached(MaximumTabs));

        var copies = new List<(Guid Source, Guid Copy)>();
        var members = new List<BrowserTab>();
        BrowserTab joiner = source;
        foreach (var member in targetMembers) {
            var resolved = copyTarget ? CopyTab(member, ids.Next(), now) : member;
            if (copyTarget) copies.Add((member.Id, resolved.Id));
            if (member.Id == sourceId) joiner = resolved;
            else members.Add(resolved);
        }
        if (copySource) {
            joiner = CopyTab(source, ids.Next(), now);
            copies.Add((source.Id, joiner.Id));
        }
        int slot = memberIndex is { } requested ? Math.Clamp(requested, 0, members.Count) : members.Count;
        members.Insert(slot, joiner);
        var group = copyTarget ? ids.Next() : target.SplitGroupId ?? ids.Next();
        var folder = copyTarget ? null : target.FolderId;
        var moving = members.Select(t => t.Id).ToHashSet();
        // Preserve empty folder positions when a current member leaves its old folder.
        var nextFolders = new FolderTree(folders).PreserveOrder(moving, tabs);
        var remaining = tabs.Where(t => !moving.Contains(t.Id)).ToList();
        int insertion;
        if (copyTarget) {
            insertion = remaining.FindIndex(t => !t.Placement.IsDurable);
            if (insertion < 0) insertion = remaining.Count;
        } else {
            int first = tabs.IndexOf(targetMembers[0]);
            insertion = tabs.Take(first).Count(t => !moving.Contains(t.Id));
        }
        foreach (var member in members) {
            member.Place(copyTarget ? TabPlacement.Current : target.Placement, folder, now, preservesSplit: true);
            member.SetSplit(group); member.MarkPosition(now);
        }
        remaining.InsertRange(insertion, members);
        tabs.Clear(); tabs.AddRange(remaining); folders.Clear(); folders.AddRange(nextFolders);
        NormalizeSplits(now);
        return new(joiner.Id, copies);
    }

    public void LeaveSplit(Guid id, DateTimeOffset now) {
        var tab = Tab(id);
        if (tab.SplitGroupId is null) return;
        var members = SplitMembers(id);
        if (members.Count > 2 && members[^1] != tab) {
            tabs.Remove(tab);
            tabs.Insert(tabs.IndexOf(members[^1]) + 1, tab);
        }
        tab.SetSplit(null); tab.MarkPosition(now); NormalizeSplits(now);
    }

    public bool StepSplitMember(Guid id, int offset, DateTimeOffset now) {
        var members = SplitMembers(id);
        int current = members.ToList().FindIndex(t => t.Id == id);
        long destination = (long)current + offset;
        return offset != 0 && destination >= 0 && destination < members.Count
            && MoveSplitMember(id, (int)destination, now);
    }

    public bool DissolveSplit(Guid id, DateTimeOffset now) {
        var members = tabs.Where(t => t.SplitGroupId == id).ToArray();
        foreach (var tab in members) { tab.SetSplit(null); tab.MarkPosition(now); }
        return members.Length > 0;
    }

    internal void RepairSplitMembership() {
        var groups = SplitMember.Repair(tabs.Select(t => new SplitMember(t.SplitGroupId, t.Placement, t.FolderId)).ToArray());
        for (int index = 0; index < tabs.Count; index++) tabs[index].SetSplit(groups[index]);
    }

    #endregion

    #region Mutators

    public IReadOnlyList<BrowserTab> SplitMembers(Guid id) {
        var tab = Tab(id);
        if (tab.SplitGroupId is not { } group) return [tab];
        int index = tabs.IndexOf(tab), first = index, last = index;
        while (first > 0 && tabs[first - 1].SplitGroupId == group) first--;
        while (last + 1 < tabs.Count && tabs[last + 1].SplitGroupId == group) last++;
        return tabs.GetRange(first, last - first + 1);
    }

    #endregion
}
