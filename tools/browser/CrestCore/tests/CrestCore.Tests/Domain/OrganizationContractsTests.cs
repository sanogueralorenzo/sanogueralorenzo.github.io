using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class OrganizationContractsTests {
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-19T12:00:00Z");
    private static Guid NewFolderId() => Guid.NewGuid();
    private static TabState Tab(string name, Guid? split = null) => new(Guid.NewGuid(), name, $"https://example.com/{name}", null,
        null, "globe", null, null, null, TabPlacement.Current, null, split, Now, null, null, null, false);
    private static BrowserTabCollection Space(params TabState[] tabs) => BrowserTabCollection.Restore(tabs, [], []);
    private static BrowserTabCollection Restored(BrowserTabCollection space) =>
        BrowserTabCollection.Restore(space.TabStates, space.Folders, space.SplitGroups);

    [Fact]
    public void FilingMovesWholeSplitsAndFolderSubtreesKeepTheirIdentities() {
        var split = Guid.NewGuid(); var first = Tab("first", split); var second = Tab("second", split);
        var space = Space(first, second);
        var root = NewFolderId(); var child = NewFolderId(); var destination = NewFolderId();
        space.AddFolder(root, "Root", TabPlacement.Current); space.AddFolder(child, "Child", parent: root);
        space.AddFolder(destination, "Saved", TabPlacement.Saved);
        space.FileTabs([first.Id], TabPlacement.Current, child, Now);
        Assert.All(space.Tabs, t => { Assert.Equal(child, t.FolderId); Assert.Equal(split, t.SplitGroupId); });
        space.MoveFolder(root, null, destination, Now.AddMinutes(1));
        Assert.Equal(new[] { destination, root, child }, space.Folders.Select(f => f.Id));
        Assert.Equal(destination, space.Folders[1].ParentId);
        Assert.All(space.Folders, f => Assert.Equal(TabPlacement.Saved, f.Location));
        Assert.All(space.Tabs, t => { Assert.Equal(TabPlacement.Saved, t.Placement); Assert.Equal(t.Url, t.SavedUrl); Assert.Equal(split, t.SplitGroupId); });
        Assert.Equal(new[] { first.Id, second.Id }, space.Tabs.Select(t => t.Id));
    }

    [Fact]
    public void RemovingFolderPromotesContentsAndPreservesCollapseClock() {
        var tab = Tab("page"); var space = Space(tab); var root = NewFolderId(); var folder = NewFolderId(); var child = NewFolderId();
        space.AddFolder(root, "Root"); space.AddFolder(folder, "Folder", parent: root); space.AddFolder(child, "Child", parent: folder);
        space.FileTabs([tab.Id], TabPlacement.Saved, folder, Now); space.CollapseFolder(child, true, Now);
        space.DeleteFolder(folder, Now.AddMinutes(1));
        Assert.Equal(root, space.Tab(tab.Id).FolderId); Assert.Equal(root, space.Folders.Single(f => f.Id == child).ParentId);
        var saved = Restored(space);
        Assert.Equal(Now, saved.Folders.Single(f => f.Id == child).CollapseModifiedAt);
        Assert.Equal(tab.Id, Assert.Single(saved.Tabs).Id); Assert.Equal(tab.Url, saved.Tabs[0].SavedUrl);
        Assert.Empty(space.Archive);
    }

    [Fact]
    public void InvalidFolderMovesLeaveTopologyAndMembershipUntouched() {
        var tab = Tab("page"); var space = Space(tab); var root = NewFolderId(); var child = NewFolderId();
        space.AddFolder(root, "Root"); space.AddFolder(child, "Child", parent: root);
        space.FileTabs([tab.Id], TabPlacement.Saved, child, Now);
        var original = space.Folders.ToArray(); var tabState = space.Tab(tab.Id).State;
        Assert.Equal(root, Assert.IsType<FolderCycle>(Assert.Throws<Rejected>(() => space.MoveFolder(root, null, child, Now)).Rejection).FolderId);
        Assert.Equal(original, space.Folders); Assert.Equal(tabState, space.Tab(tab.Id).State);
        var deepest = child;
        for (int depth = 2; depth < FolderTree.MaximumDepth; depth++) { var next = NewFolderId(); space.AddFolder(next, depth.ToString(), parent: deepest); deepest = next; }
        Assert.Equal(FolderTree.MaximumDepth, Assert.IsType<FolderDepthLimitReached>(Assert.Throws<Rejected>(() =>
            space.AddFolder(NewFolderId(), "Too deep", parent: deepest)).Rejection).Limit);
        Assert.Equal(FolderTree.MaximumDepth, space.Folders.Count);
    }

    [Fact]
    public void InsertionCannotSplitAnExistingPairAndExplicitDetachRepairsTheSurvivor() {
        var split = Guid.NewGuid(); var first = Tab("first", split); var second = Tab("second", split); var third = Tab("third");
        var space = Space(first, second, third); var folder = NewFolderId(); space.AddFolder(folder, "Destination", TabPlacement.Current);
        Assert.IsType<SplitBoundary>(Assert.Throws<Rejected>(() =>
            space.FileTabs([third.Id], TabPlacement.Current, null, Now, before: second.Id)).Rejection);
        Assert.Equal(new[] { first.Id, second.Id, third.Id }, space.Tabs.Select(t => t.Id));
        space.FileTabs([first.Id], TabPlacement.Current, folder, Now, detachSplitMembers: true);
        Assert.Null(space.Tab(first.Id).SplitGroupId); Assert.Null(space.Tab(second.Id).SplitGroupId);
        Assert.Equal(folder, space.Tab(first.Id).FolderId); Assert.Null(space.Tab(second.Id).FolderId);
    }

    [Fact]
    public void EmptyFolderBoundarySurvivesClosingItsLastTab() {
        var first = Tab("first"); var last = Tab("last"); var space = Space(first, last); var folder = NewFolderId();
        space.AddFolder(folder, "Current", TabPlacement.Current); space.FileTabs([first.Id], TabPlacement.Current, folder, Now);
        space.DismissTabs([first.Id], null, null, Now, deleting: false, ensureSelection: false, resetArchivePlacement: true);
        Assert.Equal(last.Id, Assert.Single(space.Folders).OrderAnchorTabId);
        var restored = Restored(space);
        Assert.Equal(last.Id, new FolderTree(restored.Folders).TabAnchor(folder, restored.Tabs));
        Assert.Single(space.Archive);
    }
}
