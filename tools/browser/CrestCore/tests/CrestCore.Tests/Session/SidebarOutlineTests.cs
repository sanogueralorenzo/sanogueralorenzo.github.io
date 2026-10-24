using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// The outline a Space's sidebar lists: which rows each section and folder
/// holds, in what order, how splits fold, and what a person sees of it.
public sealed class SidebarOutlineTests {
    #region Static Variables

    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-25T12:00:00Z");

    #endregion

    #region Actions - Folding

    /// A contiguous run of one split's tabs is one row that shows them in order; a
    /// lone member shows as a plain tab, and every other tab keeps its place.
    [Fact]
    public void ARunOfOneSplitIsOneRowAndALoneMemberStaysATab() {
        var group = Guid.NewGuid();
        var lone = Guid.NewGuid();
        var leading = Tab("leading");
        var head = Tab("head", split: group);
        var tail = Tab("tail", split: group);
        var single = Tab("single", split: lone);
        var trailing = Tab("trailing");

        var rows = Top(SidebarOutline.Of([leading, head, tail, single, trailing], []), TabPlacement.Current).Rows;

        Assert.Equal([leading.Id, group, single.Id, trailing.Id], rows.Select(row => row.Id));
        Assert.Equal([SidebarRowKind.Tab, SidebarRowKind.Split, SidebarRowKind.Tab, SidebarRowKind.Tab], rows.Select(row => row.Kind));
        Assert.Equal([head.Id, tail.Id], rows[1].Members);
        Assert.Equal([single.Id], rows[2].Members);
        Assert.Equal([leading.Id, head.Id, tail.Id, single.Id, trailing.Id], rows.SelectMany(row => row.Listed));
    }

    /// A split folds once: a later run of the same split shows as plain tabs, so no
    /// two rows claim one identity. Pinned tabs never fold, even with a stale split.
    [Fact]
    public void ASplitFoldsOnceAndPinnedTabsNeverFold() {
        var group = Guid.NewGuid();
        var head = Tab("head", split: group);
        var tail = Tab("tail", split: group);
        var interloper = Tab("interloper");
        var strayHead = Tab("stray head", split: group);
        var strayTail = Tab("stray tail", split: group);
        var pinned = new[] { Tab("pinned one", TabPlacement.Pinned, split: group), Tab("pinned two", TabPlacement.Pinned, split: group) };

        var outline = SidebarOutline.Of([.. pinned, head, tail, interloper, strayHead, strayTail], []);

        Assert.Equal([group, interloper.Id, strayHead.Id, strayTail.Id], Top(outline, TabPlacement.Current).Rows.Select(row => row.Id));
        Assert.Equal(pinned.Select(tab => tab.Id), Top(outline, TabPlacement.Pinned).Rows.Select(row => row.Id));
        Assert.All(Top(outline, TabPlacement.Pinned).Rows, row => Assert.Equal(SidebarRowKind.Tab, row.Kind));
    }

    /// A Start Page is a draft, not a tab the sidebar lists, in any section, and it
    /// has no place in the sidebar's order.
    [Fact]
    public void StartPagesAreListedNowhere() {
        var pinned = Tab("pinned", TabPlacement.Pinned);
        var saved = Tab("saved", TabPlacement.Saved);
        var current = Tab("current");
        TabState[] drafts = [Tab("pinned draft", TabPlacement.Pinned, startPage: true), Tab("saved draft", TabPlacement.Saved, startPage: true),
            Tab("draft", startPage: true)];

        var outline = SidebarOutline.Of([drafts[0], pinned, drafts[1], saved, current, drafts[2]], []);

        Assert.Equal([pinned.Id, saved.Id, current.Id], outline.Positions().Keys);
        Assert.All(drafts, draft => Assert.DoesNotContain(outline.Lists, list => list.Rows.Any(row => row.Members.Contains(draft.Id))));
    }

    #endregion

    #region Actions - Folders

    /// A folder takes the place of its first row in the Space's order, so a loose tab
    /// between two folders' tabs lists between the folders.
    [Fact]
    public void AFolderTakesThePlaceOfItsFirstRow() {
        var first = Folder("first", TabPlacement.Saved);
        var second = Folder("second", TabPlacement.Saved);
        var firstTab = Tab("first member", TabPlacement.Saved, first.Id);
        var between = Tab("between", TabPlacement.Saved);
        var secondTab = Tab("second member", TabPlacement.Saved, second.Id);

        var outline = SidebarOutline.Of([firstTab, between, secondTab], [first, second]);

        Assert.Equal([first.Id, between.Id, second.Id], Top(outline, TabPlacement.Saved).Rows.Select(row => row.Id));
        Assert.Equal([firstTab.Id], Inside(outline, first).Rows.Select(row => row.Id));
        Assert.Equal([secondTab.Id], Inside(outline, second).Rows.Select(row => row.Id));
    }

    /// Folders nest top-level first, each followed by its own, and every row knows
    /// the folder that lists it and how many folders hold it. A split inside a folder
    /// folds there.
    [Fact]
    public void NestedFoldersListTheirInsidesWithTheirDepth() {
        var root = Folder("root", TabPlacement.Current);
        var child = Folder("child", TabPlacement.Current, root.Id);
        var grandchild = Folder("grandchild", TabPlacement.Current, child.Id);
        var sibling = Folder("sibling", TabPlacement.Current);
        var group = Guid.NewGuid();
        var deep = Tab("deep", folder: grandchild.Id);
        var head = Tab("head", folder: sibling.Id, split: group);
        var tail = Tab("tail", folder: sibling.Id, split: group);

        var outline = SidebarOutline.Of([deep, head, tail], [sibling, root, child, grandchild]);

        Assert.Equal([(root.Id, 0), (sibling.Id, 0)], Top(outline, TabPlacement.Current).Rows.Select(row => (row.Id, row.Depth)));
        Assert.Equal([(child.Id, (Guid?)root.Id, 1)], Inside(outline, root).Rows.Select(row => (row.Id, row.ParentFolderId, row.Depth)));
        Assert.Equal([(grandchild.Id, (Guid?)child.Id, 2)], Inside(outline, child).Rows.Select(row => (row.Id, row.ParentFolderId, row.Depth)));
        Assert.Equal([(deep.Id, (Guid?)grandchild.Id, 3)], Inside(outline, grandchild).Rows.Select(row => (row.Id, row.ParentFolderId, row.Depth)));
        var split = Assert.Single(Inside(outline, sibling).Rows);
        Assert.Equal((group, SidebarRowKind.Split, 1), (split.Id, split.Kind, split.Depth));
        Assert.Equal([root.Id, child.Id, grandchild.Id, deep.Id, sibling.Id, head.Id, tail.Id], outline.Positions().Keys);
    }

    /// A folder without rows keeps its place before the tab it anchors to, or before
    /// the folder that holds that tab, and ends its list when it anchors to nothing.
    [Fact]
    public void AnEmptyFolderKeepsItsPlaceBeforeWhatItAnchorsTo() {
        var populated = Folder("populated", TabPlacement.Current);
        var member = Tab("member", folder: populated.Id);
        var loose = Tab("loose");
        var beforeLoose = Folder("before loose", TabPlacement.Current, anchor: loose.Id);
        var beforePopulated = Folder("before populated", TabPlacement.Current, anchor: member.Id);
        var last = Folder("last", TabPlacement.Current);
        var gone = Folder("anchored to a closed tab", TabPlacement.Current, anchor: Guid.NewGuid());

        var outline = SidebarOutline.Of([loose, member], [populated, last, beforePopulated, beforeLoose, gone]);

        Assert.Equal([beforeLoose.Id, loose.Id, beforePopulated.Id, populated.Id, last.Id, gone.Id],
            Top(outline, TabPlacement.Current).Rows.Select(row => row.Id));
        Assert.Empty(Inside(outline, last).Rows);
    }

    /// A collapsed folder and a collapsed section keep their rows in the outline and
    /// in the sidebar's order, and a person sees none of them.
    [Fact]
    public void ACollapsedFolderKeepsItsRowsAndShowsNone() {
        var open = Folder("open", TabPlacement.Saved);
        var collapsed = Folder("collapsed", TabPlacement.Saved, open.Id, collapsed: true);
        var inside = Tab("inside", TabPlacement.Saved, collapsed.Id);
        var beside = Tab("beside", TabPlacement.Saved, open.Id);
        var current = Tab("current");
        FolderState[] folders = [open, collapsed];

        var outline = SidebarOutline.Of([inside, beside, current], folders);

        Assert.Equal([inside.Id], Inside(outline, collapsed).Rows.Select(row => row.Id));
        Assert.Equal([open.Id, collapsed.Id, inside.Id, beside.Id, current.Id], outline.Positions().Keys);
        Assert.Equal([open.Id, collapsed.Id, beside.Id, current.Id], outline.Shown(folders, _ => true));
        Assert.Equal([current.Id], outline.Shown(folders, section => section != TabPlacement.Saved));
    }

    #endregion

    #region Actions - Order

    /// A selection is ordered as the Space's outline lists it: the tabs of a Space
    /// with pinned tabs, nested and empty folders, a split and a Start Page come back
    /// in the order the sidebar lists them, whatever order they were picked in.
    [Fact]
    public void ASelectionIsOrderedAsTheOutlineLists() {
        var group = Guid.NewGuid();
        var projects = Folder("projects", TabPlacement.Saved);
        var reading = Folder("reading", TabPlacement.Saved, projects.Id);
        var errands = Folder("errands", TabPlacement.Current);
        TabState[] tabs = [
            Tab("pinned", TabPlacement.Pinned), Tab("loose saved", TabPlacement.Saved), Tab("article", TabPlacement.Saved, reading.Id),
            Tab("plan", TabPlacement.Saved, projects.Id), Tab("draft", startPage: true), Tab("head", split: group),
            Tab("tail", split: group), Tab("errand", folder: errands.Id), Tab("last")
        ];
        FolderState[] folders = [errands, projects, reading, Folder("empty", TabPlacement.Current, anchor: tabs[5].Id)];
        var space = BrowserTabCollection.Restore(tabs, folders, []);
        var outline = SidebarOutline.Of(space.TabStates, space.Folders);
        var listed = outline.Positions().Keys.ToList();
        Guid[] picked = [.. listed.Where(id => tabs.Any(tab => tab.Id == id)).Reverse()];

        var selected = space.Select(new TabSelection(picked, [], picked));

        Assert.Equal(listed.Where(picked.Contains), selected.Roots.Select(root => root.Id));
        Assert.Equal(listed.Count, tabs.Length - 1 + folders.Length);
    }

    #endregion

    #region Actions - Support

    private static TabState Tab(string title, TabPlacement? placement = null, Guid? folder = null, Guid? split = null,
        bool startPage = false) {
        var section = placement ?? TabPlacement.Current;
        string? url = startPage ? null : $"https://example.com/{Uri.EscapeDataString(title)}";
        return new(Guid.NewGuid(), title, url, null, section.IsDurable ? url : null, "globe", null, null, null, section, folder, split,
            Now, null, null, null, false);
    }

    private static FolderState Folder(string title, TabPlacement location, Guid? parent = null, Guid? anchor = null,
        bool collapsed = false) =>
        new(Guid.NewGuid(), location, title, ParentId: parent, IsCollapsed: collapsed, OrderAnchorTabId: anchor);

    private static SidebarList Top(SidebarOutline outline, TabPlacement section) =>
        outline.Lists.Single(list => list.FolderId is null && list.Section == section);

    private static SidebarList Inside(SidebarOutline outline, FolderState folder) =>
        outline.Lists.Single(list => list.FolderId == folder.Id);

    #endregion
}
