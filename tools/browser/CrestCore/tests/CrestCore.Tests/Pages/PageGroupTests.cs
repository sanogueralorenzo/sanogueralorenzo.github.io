using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Tab groups an extension makes of an engine's pages: the core shows each as
/// the folder of the same identity in its Space's open tabs, the folder
/// follows what the engine reports, and the person's edits to the folder reach
/// the group, without ever taking a page out that the folder cannot hold.
public sealed partial class BrowserContractsTests {
    /// The folder `group` shows as, and the tabs it holds in order.
    private static (FolderState? Folder, List<Guid> Tabs) GroupFolder(CrestApp app, Guid workspace, Guid space, Guid group) {
        var held = app.Workspace(workspace).Current.Spaces.Single(candidate => candidate.Id == space);
        return (held.Folders.SingleOrDefault(folder => folder.Id == group),
            [.. held.Tabs.Where(tab => tab.FolderId == group).Select(tab => tab.Id)]);
    }

    [Fact]
    public void AnExtensionsTabGroupShowsAsAnOpenFolderThatFollowsTheGroupAndLeadsIt() {
        var session = TwoSpaceSession();
        var space = SpaceId(session["spaces"]![0]!);
        var (app, engine, binding, workspace, window) = PageHost(session);
        using var disposal = app;
        var savedTab = TabId(session["spaces"]![0]!, 0);
        var savedPage = Guid.NewGuid();
        app.Send(new OpenPage(savedPage, workspace, space, savedTab, window));
        app.Report(engine, new PageCreated(savedPage));
        var (firstTab, firstPage) = LiveTab(app, engine, workspace, window, space, "https://one.example/");
        var (secondTab, secondPage) = LiveTab(app, engine, workspace, window, space, "https://two.example/");
        var (thirdTab, thirdPage) = LiveTab(app, engine, workspace, window, space, "https://three.example/");
        var group = Guid.NewGuid();
        int issued = binding.Commands.Count;

        // The open tabs of the grouped pages file into a folder that takes the
        // group's title and color. The saved tab stays where it is, and in the
        // group, which the engine holds as reported.
        app.Report(engine, new PageGroupChanged(group, window, "Claude", TabGroupColor.Orange, IsCollapsed: false,
            [savedPage, firstPage, secondPage]));
        var (folder, tabs) = GroupFolder(app, workspace, space, group);
        Assert.Equal(("Claude", (BrandColor?)TabGroupColor.Orange.Color, TabPlacement.Current, false),
            (folder!.Title, folder.Color, folder.Location, folder.IsCollapsed));
        Assert.Equivalent(new[] { firstTab, secondTab }, tabs, strict: true);
        Assert.Equal(TabPlacement.Saved,
            app.Workspace(workspace).Current.Spaces.Single(held => held.Id == space).Tabs.Single(tab => tab.Id == savedTab).Placement);
        Assert.Equal(issued, binding.Commands.Count);

        // A page that joins or leaves moves its tab in or out.
        app.Report(engine, new PageGroupChanged(group, window, "Research", TabGroupColor.Blue, IsCollapsed: true,
            [savedPage, secondPage, thirdPage]));
        (folder, tabs) = GroupFolder(app, workspace, space, group);
        Assert.Equal(("Research", (BrandColor?)TabGroupColor.Blue.Color, true), (folder!.Title, folder.Color, folder.IsCollapsed));
        Assert.Equivalent(new[] { secondTab, thirdTab }, tabs, strict: true);
        Assert.Null(CurrentTabs(app, workspace, space).Single(tab => tab.Id == firstTab).FolderId);
        Assert.Equal(issued, binding.Commands.Count);

        // A page put away keeps its tab in the folder, and its next page joins the group.
        app.Send(new ReleasePage(thirdPage, KeepsState: true));
        app.Report(engine, new PageClosed(thirdPage, RestoreState: null));
        Assert.Equivalent(new[] { secondTab, thirdTab }, GroupFolder(app, workspace, space, group).Tabs, strict: true);
        var reopened = Guid.NewGuid();
        app.Send(new OpenPage(reopened, workspace, space, thirdTab, window));
        app.Report(engine, new PageCreated(reopened));
        var asked = Assert.IsType<GroupPages>(binding.Commands[^1]);
        Assert.Equal((group, "Research", TabGroupColor.Blue, true), (asked.GroupId, asked.Title, asked.Color, asked.IsCollapsed));
        Assert.Equivalent(new[] { secondPage, reopened, savedPage }, asked.PageIds, strict: true);

        // The person's edits reach the group; a color of their own reads as the nearest group color.
        app.Send(new RenameFolder(workspace, space, group, "Errands"));
        app.Send(new SetFolderColor(workspace, space, group, new BrandColor(0.2, 0.8, 0.4)));
        app.Send(new CollapseFolder(workspace, space, group, Collapsed: false));
        asked = Assert.IsType<GroupPages>(binding.Commands[^1]);
        Assert.Equal(("Errands", TabGroupColor.Green, false), (asked.Title, asked.Color, asked.IsCollapsed));
        Assert.Equivalent(new[] { secondPage, reopened, savedPage }, asked.PageIds, strict: true);

        // The group reporting that color back leaves the person's color alone.
        issued = binding.Commands.Count;
        app.Report(engine, new PageGroupChanged(group, window, "Errands", TabGroupColor.Green, IsCollapsed: false,
            [savedPage, secondPage, reopened]));
        Assert.Equal(new BrandColor(0.2, 0.8, 0.4), GroupFolder(app, workspace, space, group).Folder!.Color);
        Assert.Equal(issued, binding.Commands.Count);

        // The last open tab leaving takes the folder with it, and the group keeps the saved tab.
        app.Report(engine, new PageGroupChanged(group, window, "Errands", TabGroupColor.Green, IsCollapsed: false, [savedPage]));
        Assert.Null(GroupFolder(app, workspace, space, group).Folder);
        Assert.All(CurrentTabs(app, workspace, space), tab => Assert.Null(tab.FolderId));
        Assert.Equal(issued, binding.Commands.Count);
    }

    [Fact]
    public void TheDeviceStoreKeepsAPersistentSessionsGroupSoItsFolderMakesItAgainAfterARelaunch() {
        using var directory = new StorageDirectory();
        var group = Guid.NewGuid();
        Guid space, tab;
        {
            var (app, workspace, spaces) = DeviceApp(directory);
            using var disposal = app;
            var binding = new RecordingEngine();
            var engine = app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, IsDefault: true), binding.Run);
            var window = Guid.NewGuid();
            app.Send(new OpenWindow(window, workspace, Saved: false, null, null, [], RestoresTabs: true));
            space = SpaceId(spaces[0]!);
            (tab, var page) = LiveTab(app, engine, workspace, window, space);
            // An untitled group keeps its own blank title beside its folder's name.
            app.Report(engine, new PageGroupChanged(group, window, "", TabGroupColor.Cyan, IsCollapsed: false, [page]));
            Assert.Equal("Untitled Folder", GroupFolder(app, workspace, space, group).Folder!.Title);
        }

        var (relaunched, persistent, _) = DeviceApp(directory);
        using var relaunchedDisposal = relaunched;
        var restarted = new RecordingEngine();
        var engineAgain = relaunched.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, IsDefault: true),
            restarted.Run);
        var shown = Guid.NewGuid();
        relaunched.Send(new OpenWindow(shown, persistent, Saved: false, null, null, [], RestoresTabs: true));
        Assert.Equal([tab], GroupFolder(relaunched, persistent, space, group).Tabs);
        var reopened = Guid.NewGuid();
        relaunched.Send(new OpenPage(reopened, persistent, space, tab, shown));
        relaunched.Report(engineAgain, new PageCreated(reopened));

        var asked = Assert.IsType<GroupPages>(restarted.Commands[^1]);
        Assert.Equal((group, "", TabGroupColor.Cyan, false), (asked.GroupId, asked.Title, asked.Color, asked.IsCollapsed));
        Assert.Equal([reopened], asked.PageIds);
    }

    [Fact]
    public void DeletingAGroupsFolderTakesEveryPageOutOfTheGroup() {
        var session = TwoSpaceSession();
        var space = SpaceId(session["spaces"]![0]!);
        var (app, engine, binding, workspace, window) = PageHost(session);
        using var disposal = app;
        var (firstTab, firstPage) = LiveTab(app, engine, workspace, window, space, "https://one.example/");
        var (secondTab, secondPage) = LiveTab(app, engine, workspace, window, space, "https://two.example/");
        var group = Guid.NewGuid();
        app.Report(engine, new PageGroupChanged(group, window, "Claude", TabGroupColor.Orange, IsCollapsed: false, [firstPage, secondPage]));

        app.Send(new DeleteFolder(workspace, space, group));

        var asked = Assert.IsType<GroupPages>(binding.Commands[^1]);
        Assert.Equal(group, asked.GroupId);
        Assert.Empty(asked.PageIds);
        Assert.All(CurrentTabs(app, workspace, space), tab => Assert.Null(tab.FolderId));
        Assert.Equal(2, CurrentTabs(app, workspace, space).Count(tab => tab.Id == firstTab || tab.Id == secondTab));
    }
}
