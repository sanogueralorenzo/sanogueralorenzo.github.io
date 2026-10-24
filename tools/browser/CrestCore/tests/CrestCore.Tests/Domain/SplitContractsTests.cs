using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class SplitContractsTests {
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-19T12:00:00Z");
    private static TabState Tab(string title, TabPlacement? placement = null, Guid? split = null) =>
        new(Guid.NewGuid(), title, "https://example.com/" + title, null,
            placement?.IsDurable == true ? "https://saved.example/" : null, "globe", null, null, null, placement ?? TabPlacement.Current,
            null, split, Now, null, "Custom " + title, null, true);
    private static BrowserTabCollection Space(params TabState[] tabs) => BrowserTabCollection.Restore(tabs, [], []);
    private static BrowserTabCollection Restored(BrowserTabCollection space) =>
        BrowserTabCollection.Restore(space.TabStates, space.Folders, space.SplitGroups);

    [Fact]
    public void JoiningDurableTabsCopiesTheDestinationRunAndKeepsOriginalsUntouched() {
        var group = Guid.NewGuid();
        var space = Space(Tab("first", TabPlacement.Saved, group), Tab("second", TabPlacement.Saved, group), Tab("source", TabPlacement.Pinned));
        var first = space.Tabs[0]; var source = space.Tabs[2];
        var originals = space.TabStates.ToArray();
        var result = space.JoinSplit(source.Id, first.Id, 1, new SystemIdSource(), Now.AddMinutes(1));
        Assert.Equal(originals, space.TabStates.Take(3));
        Assert.Equal(3, result.Copies.Count);
        var members = space.SplitMembers(result.SelectedTab);
        Assert.Equal(new[] { "first", "source", "second" }, members.Select(t => t.Title));
        Assert.All(members, t => {
            Assert.Equal(TabPlacement.Current, t.Placement); Assert.Null(t.SavedUrl); Assert.Null(t.FolderId);
            Assert.False(t.KeepsPageLoaded);
            Assert.Equal("Custom " + t.Title, t.CustomTitle); Assert.NotEqual(group, t.SplitGroupId);
        });
        Assert.Single(members.Select(t => t.SplitGroupId).Distinct());
    }

    [Fact]
    public void ReorderingDurableMembersKeepsTheirIdentityAndPlacement() {
        var group = Guid.NewGuid();
        var first = Tab("first", TabPlacement.Saved, group); var second = Tab("second", TabPlacement.Saved, group);
        var space = Space(first, second);
        var result = space.JoinSplit(second.Id, first.Id, 0, new SystemIdSource(), Now);
        Assert.Empty(result.Copies); Assert.Equal(new[] { second.Id, first.Id }, space.Tabs.Select(t => t.Id));
        Assert.All(space.Tabs, t => { Assert.Equal(TabPlacement.Saved, t.Placement); Assert.Equal(group, t.SplitGroupId); });
    }

    [Fact]
    public void LeavingMiddleOfRunKeepsSurvivorsContiguousAndExplicitMutationDissolvesSingleton() {
        var group = Guid.NewGuid();
        var first = Tab("first", split: group); var second = Tab("second", split: group);
        var third = Tab("third", split: group); var tail = Tab("tail");
        var space = Space(first, second, third, tail);
        space.LeaveSplit(second.Id, Now);
        Assert.Equal(new[] { first.Id, third.Id, second.Id, tail.Id }, space.Tabs.Select(t => t.Id));
        Assert.Equal(group, space.Tab(first.Id).SplitGroupId); Assert.Equal(group, space.Tab(third.Id).SplitGroupId);
        Assert.Null(space.Tab(second.Id).SplitGroupId);
        space.LeaveSplit(first.Id, Now.AddMinutes(1));
        Assert.Null(space.Tab(first.Id).SplitGroupId); Assert.Null(space.Tab(third.Id).SplitGroupId);
        Assert.Equal(Now.AddMinutes(1), space.Tab(third.Id).State.PositionModifiedAt);
    }

    [Fact]
    public void FullSplitRefusesWithoutCopyingOrChangingAnyTab() {
        var group = Guid.NewGuid();
        var space = Space([.. Enumerable.Range(0, 4).Select(i => Tab("member" + i, TabPlacement.Saved, group)), Tab("source")]);
        var before = space.TabStates.ToArray();
        Assert.Equal(BrowserTabCollection.MaximumSplitMembers, Assert.IsType<SplitLimitReached>(Assert.Throws<Rejected>(() =>
            space.JoinSplit(space.Tabs[^1].Id, space.Tabs[0].Id, null, new SystemIdSource(), Now)).Rejection).Limit);
        Assert.Equal(before, space.TabStates);
    }

    [Fact]
    public void RestoreRepairsMalformedRunsWithoutErasingSingletonMembershipOrPositionClock() {
        var group = Guid.NewGuid(); var single = Tab("single", split: group);
        var repeated = Tab("repeated", split: group); var pinned = Tab("pinned", TabPlacement.Pinned, Guid.NewGuid());
        var restored = Space(single, Tab("separator"), repeated, pinned);
        Assert.Equal(group, restored.Tab(single.Id).SplitGroupId);
        Assert.Null(restored.Tab(repeated.Id).SplitGroupId); Assert.Null(restored.Tab(pinned.Id).SplitGroupId);
        Assert.All(restored.TabStates, t => Assert.Null(t.PositionModifiedAt));
        Assert.Equal(restored.TabStates, Restored(restored).TabStates);
    }
}
