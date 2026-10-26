using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void ExternalOpensUseTheFrontRegularWindowAndReopenItsCurrentSpace() {
        using var directory = new StorageDirectory();
        var (app, workspace, spaces) = DeviceApp(directory);
        using var disposal = app;
        var (first, second) = (SpaceId(spaces[0]!), SpaceId(spaces[1]!));
        Guid back = Guid.NewGuid(), front = Guid.NewGuid(), privateWindow = Guid.NewGuid();
        app.Send(new OpenWindow(back, workspace, Saved: true, null, first, [], RestoresTabs: true));
        app.Send(new OpenWindow(front, workspace, Saved: true, null, second, [], RestoresTabs: true));
        var privateWorkspace = TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, Seed: null)));
        app.Send(new OpenWindow(privateWindow, privateWorkspace, Saved: false, null, null, [], RestoresTabs: true));
        ExternalOpenPlacement Destination(params Guid[] stacked) => app.Query(new ExternalOpenDestination(stacked));

        Assert.Equal(new ExternalOpenPlacement(front, second, OpensWindow: false), Destination(privateWindow, front, back));
        Assert.Equal(new ExternalOpenPlacement(back, first, OpensWindow: false), Destination(back, front));
        app.Send(new CloseWindow(front));
        app.Send(new CloseWindow(back));
        Assert.Equal(new ExternalOpenPlacement(front, second, OpensWindow: true), Destination(privateWindow));
    }

    [Fact]
    public void PreviewLinksAndNewWindowsUseFixedSelectionGestures() {
        var (document, space, tab) = SavedSession();
        var (app, _, _, workspace, window) = PageHost(document["session"]!);
        using var disposal = app;
        Guid saved = Guid.NewGuid();
        app.Send(new OpenPage(saved, workspace, space, tab, window));
        LinkNavigationDecision Follow(string url, ShortcutModifiers held = ShortcutModifiers.None) =>
            app.Query(new LinkNavigation(saved, url, new LinkGesture(true, true, held, false))).Decision;
        Assert.Equal(LinkNavigationDecision.ForegroundTab, Follow("https://webkit.org/"));
        Assert.Equal(LinkNavigationDecision.Navigate, Follow("https://example.com/other"));
        Assert.Equal(LinkNavigationDecision.ForegroundTab, Follow("https://webkit.org/", ShortcutModifiers.Option));
        Assert.Equal(LinkNavigationDecision.BackgroundTab, Follow("https://webkit.org/", ShortcutModifiers.Command));
        Assert.Equal(LinkNavigationDecision.ForegroundTab,
            Follow("https://webkit.org/", ShortcutModifiers.Command | ShortcutModifiers.Shift));
        bool Selects(ShortcutModifiers held, bool middle = false) =>
            app.Query(new OpenedWindowSelection(new LinkGesture(false, true, held, middle))).Selects;
        Assert.True(Selects(ShortcutModifiers.None));
        Assert.False(Selects(ShortcutModifiers.Command));
        Assert.False(Selects(ShortcutModifiers.None, middle: true));
        Assert.True(Selects(ShortcutModifiers.Command | ShortcutModifiers.Shift));
        Assert.True(Selects(ShortcutModifiers.Shift, middle: true));
    }
}
