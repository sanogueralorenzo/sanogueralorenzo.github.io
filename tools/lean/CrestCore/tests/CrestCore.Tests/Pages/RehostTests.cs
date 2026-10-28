using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// A page moving to another engine: the old engine closes it and nothing it
/// asked or reports afterwards counts, the new engine creates it and then
/// loads the address it showed.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void APageMovesToAnotherEngineThatLoadsWhatItShowedAndTheOldEnginesQuestionsEnd() {
        var (app, webKit, webKitBinding, page, workspace, window, space, _) = LivePage();
        using var disposal = app;
        var chromiumBinding = new RecordingEngine();
        var chromium = app.RegisterEngine(new EngineRegistration(EngineKind.Chromium, [.. EngineCapability.Required, EngineCapability.Reader],
            IsDefault: false), chromiumBinding.Run);
        const string article = "https://example.com/article";
        app.Send(new Navigate(page, article));
        var prompt = Guid.NewGuid();
        app.Report(webKit, new ScriptDialogOpened(prompt, page, Confirmation));
        app.Drain();

        // The old engine closes the page keeping its history, its question ends, and the new engine creates the page heading to what it showed.
        app.Send(new RehostPage(page, EngineKind.Chromium));
        Assert.Equal(new CheckBeforeUnload(page), webKitBinding.Commands[^1]);
        Assert.Empty(chromiumBinding.Commands);
        app.Report(webKit, new BeforeUnloadAnswered(page, Proceeds: true));
        var moved = app.Drain();
        var state = Assert.Single(moved.OfType<PageChanged>()).Page;
        Assert.Equal((EngineKind.Chromium, PagePhase.Opening, article), (state.Engine, state.Phase, state.Live.Address));
        Assert.Contains(new PromptSettled(prompt), moved);
        Assert.Equal(new ClosePage(page, KeepsState: true), webKitBinding.Commands[^1]);
        var profile = Assert.IsType<CreatePage>(Assert.Single(chromiumBinding.Commands)).ProfileId;
        Assert.Equal(new CreatePage(page, profile, IsPrivate: false, window, RestoreState: null), chromiumBinding.Commands[0]);

        // What the old engine reports about the page changes nothing, and the new one loads once it has created it.
        app.Report(webKit, new PageClosed(page, RestoreState: null));
        app.Report(webKit, new NavigationCommitted(page, "https://example.com/elsewhere", SameDocument: false));
        Assert.Empty(app.Drain());
        app.Report(chromium, new PageCreated(page));
        Assert.Equal(PagePhase.Live, Assert.IsType<PageChanged>(Assert.Single(app.Drain())).Page.Phase);
        Assert.Equal(new LoadPage(page, article), chromiumBinding.Commands[^1]);

        // A page already on the engine stays, and one that is not open cannot move.
        int commands = chromiumBinding.Commands.Count;
        Assert.Empty(app.Send(new RehostPage(page, EngineKind.Chromium)));
        Assert.Equal(commands, chromiumBinding.Commands.Count);
        Assert.Equal(new UnknownPage(workspace), Refusal(app, new RehostPage(workspace, EngineKind.WebKit)));

    }
}
