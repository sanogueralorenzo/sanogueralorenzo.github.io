using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Folder and split intents refuse with the rule they break and change nothing
/// when they do; asking whether the core would accept one changes nothing.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void FoldersStayInSectionsThatHoldThemAndWithinTheSpacesFolderLimit() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        var folders = space["folders"]!.AsArray();
        while (folders.Count < FolderTree.MaximumCount - 1)
            folders.Add(new JsonObject { ["id"] = SwiftId(Guid.NewGuid()), ["title"] = "Filler", ["location"] = "saved" });
        using var device = new TestDevice(session);
        var core = device.Authority;
        CreateFolder Creating(TabPlacement placement, Guid? parent = null) =>
            new(device.Workspace, f.Space, Guid.NewGuid(), placement, parent, "Folder", null, null, [], LeavesSplits: false);

        Assert.IsType<InvalidFolderPlacement>(Assert.Throws<Rejected>(() => device.Send(Creating(TabPlacement.Pinned))).Rejection);
        var missing = Guid.NewGuid();
        Assert.Equal(missing, Assert.IsType<UnknownFolder>(Assert.Throws<Rejected>(() =>
            device.Send(Creating(TabPlacement.Saved, missing))).Rejection).FolderId);
        device.Send(Creating(TabPlacement.Current));
        var full = core.Current;
        var refusal = device.Query(new CanSend(Creating(TabPlacement.Saved))).Refusal;
        Assert.Equal(FolderTree.MaximumCount, Assert.IsType<FolderLimitReached>(refusal).Limit);
        Assert.IsType<FolderLimitReached>(Assert.Throws<Rejected>(() => device.Send(Creating(TabPlacement.Saved))).Rejection);
        Assert.Same(full, core.Current);
    }

    [Fact]
    public void JoiningASavedTabCopiesItsPageUnderAnIdentityTheCoreGivesAndShowsTheCopy() {
        var f = SavedSession(); var session = f.Document["session"]!; var space = session["spaces"]![0]!;
        var target = space["tabs"]![0]!.DeepClone(); var targetId = Guid.NewGuid();
        target["id"] = SwiftId(targetId); target["placement"] = "current"; target["folderID"] = null;
        target["splitGroupID"] = null; target["savedURL"] = null;
        var draft = target.DeepClone(); var draftId = Guid.NewGuid();
        draft["id"] = SwiftId(draftId); draft["url"] = null; draft["title"] = "Start Page";
        space["tabs"]!.AsArray().Add(target); space["tabs"]!.AsArray().Add(draft);
        using var device = new TestDevice(session);
        var core = device.Authority;
        var window = device.Showing(session);
        var copy = Guid.NewGuid();
        device.Ids.Supply([copy]);

        Assert.Equal(draftId, Assert.IsType<WebPagesOnly>(Assert.Throws<Rejected>(() =>
            device.Send(new JoinSplit(device.Workspace, window, f.Space, draftId, targetId, null))).Rejection).TabId);
        // The saved tab's page has moved on before its navigation was recorded.
        device.ShowPage(window, f.Space, f.Tab, PageSnapshot.Blank with { Url = "https://example.com/live", Title = "Live page" });
        var copied = Assert.Single(device.Send(new JoinSplit(device.Workspace, window, f.Space, f.Tab, targetId, null))
            .OfType<TabCopied>());

        // The saved tab stays as it was; its copy shows what its page shows now.
        Assert.Equal((f.Tab, copy), (copied.SourceTabId, copied.CopyTabId));
        var joined = core.Current.Spaces[0];
        var original = joined.Tabs.Single(tab => tab.Id == f.Tab);
        Assert.Equal((TabPlacement.Saved, "https://example.com/article#one"), (original.Placement, original.Url));
        Assert.Equal(("https://example.com/live", "Live page"), (joined.Tabs.Single(tab => tab.Id == copy).Url,
            joined.Tabs.Single(tab => tab.Id == copy).Title));
        Assert.Equal(joined.Tabs.Single(tab => tab.Id == targetId).SplitGroupId, joined.Tabs.Single(tab => tab.Id == copy).SplitGroupId);
        Assert.Equal(copy, device.Tab(window, f.Space));
        Assert.Equal(copy, Assert.IsType<AlreadyInSplit>(Assert.Throws<Rejected>(() =>
            device.Send(new JoinSplit(device.Workspace, window, f.Space, copy, targetId, null))).Rejection).TabId);
    }
}
