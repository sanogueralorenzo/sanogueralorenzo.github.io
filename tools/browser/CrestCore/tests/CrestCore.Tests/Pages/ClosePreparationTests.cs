using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Closing asks each page it would close whether it may go, one at a time: the
/// first that asks to stay ends it not allowed, a page that goes has nothing to
/// ask, a page that shows another document after agreeing voids the answer, a
/// window asks only the pages that go with it, and quitting with downloads in
/// progress asks the person.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ClosingAsksEachPageInTurnAndTheFirstThatStaysEndsItNotAllowed() {
        var (app, engine, binding, page, workspace, window, space, _) = LivePage();
        using var disposal = app;
        var other = Guid.NewGuid();
        app.Send(new OpenPage(other, workspace, space, null, window));
        app.Report(engine, new PageCreated(other));
        app.Drain();

        var request = Guid.NewGuid();
        Assert.Empty(app.Send(new PrepareToClosePages(request, [page, other])));
        Assert.Equal(new CheckBeforeUnload(page), binding.Commands[^1]);
        Assert.Equal(new ClosePreparationUnderway(request), Refusal(app, new PrepareToQuit(Guid.NewGuid())));

        app.Report(engine, new BeforeUnloadAnswered(page, Proceeds: true));
        Assert.Equal(new CheckBeforeUnload(other), binding.Commands[^1]);
        app.Report(engine, new BeforeUnloadAnswered(other, Proceeds: false));
        Assert.Equal([new CloseReady(request, Allowed: false)], app.Drain());
    }

    [Fact]
    public void APageThatGoesHasNothingToAskAndOneThatMovesOnVoidsItsAnswer() {
        var (app, _, _, page, _, window, _, _) = LivePage();
        using var disposal = app;

        // The page waited on goes, so the close is ready.
        var first = Guid.NewGuid();
        app.Send(new PrepareToClosePages(first, [page]));
        Assert.Contains(new CloseReady(first, Allowed: true), app.Send(new ReleasePage(page, KeepsState: false)));

        // A page that agreed, then showed another document, voids the answer.
        var (again, engineAgain, bindingAgain, pageAgain, _, _, _, _) = LivePage();
        using var disposalAgain = again;
        var second = Guid.NewGuid();
        again.Send(new PrepareToClosePages(second, [pageAgain]));
        again.Report(engineAgain, new NavigationCommitted(pageAgain, "https://example.org/", SameDocument: false));
        again.Report(engineAgain, new BeforeUnloadAnswered(pageAgain, Proceeds: true));
        Assert.Contains(new CloseReady(second, Allowed: false), again.Drain());
        Assert.Equal(new CheckBeforeUnload(pageAgain), bindingAgain.Commands[^1]);
    }

    [Fact]
    public void ClosingAWindowAsksOnlyThePagesThatGoWithIt() {
        var session = TwoSpaceSession();
        var (app, engine, binding, workspace, window) = PageHost(session);
        using var disposal = app;
        var (space, lent) = (session["spaces"]![0]!, session["spaces"]![1]!);
        Guid Live(Guid owner, Guid spaceId, Guid? tabId, Guid host) {
            var page = Guid.NewGuid();
            app.Send(new OpenPage(page, owner, spaceId, tabId, host));
            app.Report(engine, new PageCreated(page));
            return page;
        }
        Live(workspace, SpaceId(space), TabId(space, 0), window);
        // A torn-off tab's window borrows its Space, and the private window
        // keeps a workspace of its own.
        var borrowed = TestWorkspaces.Borrow(app, workspace, lent);
        var borrowedWindow = Guid.NewGuid();
        app.Send(new OpenWindow(borrowedWindow, borrowed, Saved: false, null, null, [], RestoresTabs: true));
        var borrowedPage = Live(borrowed, SpaceId(lent), null, borrowedWindow);
        var privateWorkspace = TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, Seed: null)));
        var privateWindow = Guid.NewGuid();
        app.Send(new OpenWindow(privateWindow, privateWorkspace, Saved: false, null, null, [], RestoresTabs: true));
        var privatePage = Live(privateWorkspace, app.Workspace(privateWorkspace).Current.Spaces.Single().Id, null, privateWindow);
        app.Drain();

        // The borrowed window's page goes with it, so it is asked.
        var torn = Guid.NewGuid();
        Assert.Empty(app.Send(new PrepareToCloseWindows(torn, [borrowedWindow])));
        Assert.Equal(new CheckBeforeUnload(borrowedPage), binding.Commands[^1]);

        // The workspace's other windows keep an ordinary window's pages, so it
        // asks none and is ready at once, even while another close waits.
        int asked = binding.Commands.Count;
        var ordinary = Guid.NewGuid();
        Assert.Equal([new CloseReady(ordinary, Allowed: true)], app.Send(new PrepareToCloseWindows(ordinary, [window])));
        Assert.Equal(asked, binding.Commands.Count);
        app.Report(engine, new BeforeUnloadAnswered(borrowedPage, Proceeds: true));
        Assert.Equal([new CloseReady(torn, Allowed: true)], app.Drain());

        // The private window's pages go with it, as does every other page of
        // its workspace, whichever window hosts it, and one may keep it open.
        var privateQuick = Live(privateWorkspace, app.Workspace(privateWorkspace).Current.Spaces.Single().Id, null, window);
        app.Drain();
        var closingPrivate = Guid.NewGuid();
        app.Send(new PrepareToCloseWindows(closingPrivate, [privateWindow]));
        Assert.Equal(new CheckBeforeUnload(privatePage), binding.Commands[^1]);
        app.Report(engine, new BeforeUnloadAnswered(privatePage, Proceeds: true));
        Assert.Equal(new CheckBeforeUnload(privateQuick), binding.Commands[^1]);
        app.Report(engine, new BeforeUnloadAnswered(privateQuick, Proceeds: false));
        Assert.Equal([new CloseReady(closingPrivate, Allowed: false)], app.Drain());
    }

    [Fact]
    public void QuittingWithDownloadsInProgressAsksThePerson() {
        var (app, engine, _, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var profile = ProfileOf(app, workspace, space);
        app.Report(engine, new EngineDownloadChanged(Transfer(profile, page, EngineDownloadState.Downloading, received: 10)));
        app.Drain();

        var request = Guid.NewGuid();
        app.Send(new PrepareToQuit(request));
        app.Report(engine, new BeforeUnloadAnswered(page, Proceeds: true));
        var asked = Assert.IsType<QuitWithDownloadsAsked>(Assert.Single(app.Drain()));
        Assert.Equal((request, 1), (asked.RequestId, asked.LiveDownloads));
        Assert.Equal([new PromptSettled(asked.PromptId), new CloseReady(request, Allowed: true)],
            app.Send(new AnswerQuitWithDownloads(asked.PromptId, Quits: true)));
    }
}
