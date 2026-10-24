using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class NativeSessionAuthority {
    #region Variables

    /// What a folder created without a title is called.
    internal const string NewFolderTitle = "New Folder";

    #endregion

    #region Actions - Splits

    /// Joins `tabId` to the split of `targetId` in `edited`, the organization
    /// of `space`, and shows the joined tab in the issuing window. A copy
    /// starts from where its source's page is now; see `StartFromSourcePage`.
    /// A durable target's split copied into new tabs keeps its name, icon and
    /// tint.
    internal SessionEdit Joining(SessionState basis, SpaceState space, BrowserTabCollection edited, Guid windowId, Guid tabId, Guid targetId,
        int? index, Pages? pages, DateTimeOffset now, IIdSource ids) {
        var target = edited.Tab(targetId);
        var durableGroup = target.Placement.IsDurable ? target.SplitGroupId : null;
        var joined = edited.JoinSplit(tabId, targetId, index, ids, now);
        foreach (var (source, copyId) in joined.Copies) StartFromSourcePage(edited.Tab(copyId), source, windowId, pages);
        if (durableGroup is { } copied && joined.Copies.Any(pair => pair.Source == targetId)
            && edited.Tab(joined.SelectedTab).SplitGroupId is { } copy)
            edited.CopySplitMetadata(copied, copy, now);
        edited.PruneSplitMetadata();
        var followUp = new WindowFollowUp(IssuingWindow(windowId)).ShowTab(space.Id, joined.SelectedTab).ShowSpace(space.Id);
        return new(Replacing(basis, edited.Capture(space)), SyncStaging.Edit, followUp,
            new([.. joined.Copies.Select(pair => new SessionTabCopy(pair.Source, pair.Copy))], null));
    }

    /// `space`'s organization after `edit`, with the Space's other records kept.
    internal SessionEdit Organizing(SessionState basis, Guid spaceId, SyncStaging staging, Action<BrowserTabCollection> edit) {
        var space = Editable(basis, spaceId);
        var edited = BrowserTabCollection.Restore(space);
        edit(edited);
        return new(Replacing(basis, edited.Capture(space)), staging);
    }

    #endregion

    #region Actions - Split identity

    /// A split's name, icon or tint, which only a split of two or more tabs
    /// has. `choose` sets the field; `stamp` records when, so each field merges
    /// on its own. A choice that is already the split's changes nothing.
    internal SessionEdit Identifying(SessionState basis, Guid spaceId, Guid groupId, DateTimeOffset now,
        Func<SplitGroupState, SplitGroupState> choose, Func<SplitGroupState, DateTimeOffset, SplitGroupState> stamp) {
        var space = Editable(basis, spaceId);
        var run = space.Tabs.SkipWhile(tab => tab.SplitGroupId != groupId).TakeWhile(tab => tab.SplitGroupId == groupId);
        if (run.Take(2).Count() < 2) throw new Rejected(new UnknownSplitGroup(groupId));
        var existing = space.SplitGroups.FirstOrDefault(group => group.Id == groupId);
        var current = existing ?? new SplitGroupState(groupId);
        var chosen = choose(current);
        if (chosen == current) return new(basis, SyncStaging.Edit);
        var edited = stamp(chosen, BrowserEditTimestamp.Normalize(now));
        IReadOnlyList<SplitGroupState> groups = existing is null ? [.. space.SplitGroups, edited]
            : [.. space.SplitGroups.Select(candidate => candidate.Id == groupId ? edited : candidate)];
        return new(Replacing(basis, space with { SplitGroups = groups }), SyncStaging.Edit);
    }

    #endregion
}
