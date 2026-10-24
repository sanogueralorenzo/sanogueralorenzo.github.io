using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Agent preferences are device state: off until the person turns them on,
/// kept beside the session and never synced; the agents connected now live in
/// memory only. An agent reaches only the Spaces the person allowed of their
/// own session, never a private window's, one being deleted, a locked Space's
/// tabs or Crest's own views, and lets go of any tab it may no longer use.
public sealed partial class BrowserContractsTests {
    private static readonly AgentIdentity Claude = new("Q6L2SF6YDW", "com.anthropic.claude-code", null, null);

    private static AgentPreferences AgentPreferencesIn(IReadOnlyList<Change> changes) =>
        Assert.Single(changes.OfType<AgentPreferencesChanged>()).Preferences;

    private static IReadOnlyList<AgentSessionState> AgentSessionsIn(IReadOnlyList<Change> changes) =>
        changes.OfType<AgentSessionsChanged>().Last().Sessions;

    /// Turns agents on for `space`, allows Claude and connects it.
    private static Guid ConnectClaude(CrestApp app, Guid space) {
        app.Send(new SetAgents(true));
        app.Send(new AllowAgentSpace(space, true));
        app.Send(new ApproveAgent(new ApprovedAgent(Claude, "claude")));
        var session = Guid.NewGuid();
        app.Send(new BeginAgentSession(session, Claude, "claude"));
        return session;
    }

    [Fact]
    public void AgentsStayOffUntilChosenAndEveryChoiceSurvivesARelaunchButNoConnection() {
        using var directory = new StorageDirectory();
        AgentPreferences chosen;
        Guid session;
        {
            var (app, _, spaces) = DeviceApp(directory);
            using var disposal = app;
            var space = SpaceId(spaces[0]!);
            Assert.Equal(AgentPreferences.Off, app.Query(new GetAgentPreferences()));
            // An agent the person never allowed does not connect.
            app.Send(new SetAgents(true));
            Assert.IsType<AgentNotApproved>(Assert.Throws<Rejected>(() =>
                app.Send(new BeginAgentSession(Guid.NewGuid(), Claude, "claude"))).Rejection);
            session = ConnectClaude(app, space);
            chosen = AgentPreferencesIn(app.Send(new SetAgentScripts(true)));
            Assert.Equal(new AgentPreferences(true, true, [space], [new ApprovedAgent(Claude, "claude")]), chosen);
            Assert.Equal([space], app.Query(new AgentReach(session)).Spaces.Select(reached => reached.SpaceId));

            // An identity must name a program, by its signature or its path.
            foreach (var identity in new AgentIdentity[] {
                new(null, null, "relative/agent", null), new("Q6L2SF6YDW", null, null, null),
                new("Q6L2SF6YDW", "com.example", "/usr/bin/agent", null), new(null, null, null, null)
            }) {
                Assert.IsType<InvalidAgent>(Assert.Throws<Rejected>(() =>
                    app.Send(new ApproveAgent(new ApprovedAgent(identity, "agent")))).Rejection);
            }
            Assert.IsType<InvalidAgent>(Assert.Throws<Rejected>(() =>
                app.Send(new ApproveAgent(new ApprovedAgent(new(null, null, "/usr/local/bin/node", "x"), "‮\u0007 ")))).Rejection);
        }

        {
            var (relaunched, _, _) = DeviceApp(directory);
            using var disposal = relaunched;
            Assert.Equal(chosen, relaunched.Query(new GetAgentPreferences()));
            // No agent stays connected across a launch.
            Assert.Equal(new AgentReachList(null, []), relaunched.Query(new AgentReach(session)));
            // Turning agents off keeps what the person chose for next time.
            Assert.Equal(chosen with { IsOn = false }, AgentPreferencesIn(relaunched.Send(new SetAgents(false))));
            Assert.Empty(AgentPreferencesIn(relaunched.Send(new ForgetAgent(Claude))).Agents);
        }

        var (third, _, _) = DeviceApp(directory);
        using var thirdDisposal = third;
        Assert.Equal(chosen with { IsOn = false, Agents = [] }, third.Query(new GetAgentPreferences()));
    }

    [Fact]
    public void AnAgentReachesOnlyAllowedSpacesOfThePersonsOwnSessionAndNeverCrestsOwnViews() {
        using var app = new CrestApp();
        var session = TwoSpaceSession();
        var (first, second) = (SpaceId(session["spaces"]![0]!), SpaceId(session["spaces"]![1]!));
        var workspace = TestWorkspaces.Open(app, session);
        var privateWorkspace = TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, null)));
        var privateSpace = app.Workspace(privateWorkspace).Current.Spaces[0].Id;
        TestWorkspaces.Borrow(app, workspace, session["spaces"]![0]!);
        var agent = ConnectClaude(app, first);

        foreach (var unavailable in new[] { privateSpace, Guid.NewGuid() })
            Assert.Equal(new AgentSpaceUnavailable(unavailable), Assert.Throws<Rejected>(() =>
                app.Send(new AllowAgentSpace(unavailable, true))).Rejection);

        // Crest's own views, browser and extension pages and files are never an
        // agent's, even in an allowed Space; a web page or a blank one is.
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, null, null, [], RestoresTabs: true));
        var (page, blank, settings) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        app.Send(new OpenTab(workspace, window, first, page, new TabContent("https://example.com/", null, "Example"),
            TabPlacement.Current, null, Shows: false));
        app.Send(new OpenTab(workspace, window, first, blank, new TabContent("about:blank", null, null),
            TabPlacement.Current, null, Shows: false));
        app.Send(new OpenTab(workspace, window, first, settings, new TabContent(null, NativeView.Settings, null),
            TabPlacement.Current, null, Shows: false));
        var internals = new[] { "chrome://settings/", "chrome-extension://abcdefghijklmnop/options.html", "file:///etc/hosts" }
            .Select(address => {
                var tab = Guid.NewGuid();
                app.Send(new OpenTab(workspace, window, first, tab, new TabContent(address, null, null), TabPlacement.Current,
                    null, Shows: false));
                return tab;
            }).ToArray();
        var reached = Assert.Single(app.Query(new AgentReach(agent)).Spaces);
        Assert.Equal(first, reached.SpaceId);
        Assert.Contains(reached.Tabs, tab => tab.TabId == page && !tab.Claimed);
        Assert.Contains(reached.Tabs, tab => tab.TabId == blank);
        foreach (var unreachable in internals.Append(settings)) {
            Assert.DoesNotContain(reached.Tabs, tab => tab.TabId == unreachable);
            Assert.Equal(new AgentTabUnavailable(unreachable), Assert.Throws<Rejected>(() =>
                app.Send(new ClaimAgentTab(agent, unreachable))).Rejection);
        }

        // A tab of a Space the person did not allow, or no tab at all, is
        // never claimed, however its identity was learned.
        var elsewhere = app.Workspace(workspace).Current.Spaces.Single(space => space.Id == second).Tabs[0].Id;
        foreach (var tab in new[] { elsewhere, Guid.NewGuid() })
            Assert.Equal(new AgentTabUnavailable(tab), Assert.Throws<Rejected>(() => app.Send(new ClaimAgentTab(agent, tab))).Rejection);
        Assert.Equal([page], Assert.Single(AgentSessionsIn(app.Send(new ClaimAgentTab(agent, page)))).TabIds);
    }

    [Fact]
    public void ALockedSpaceShowsAgentsItsNameAndNoTabs() {
        using var app = new CrestApp();
        var session = GuardedSession();
        var workspace = TestWorkspaces.Open(app, session);
        var space = Identity(session).Space;
        var agent = ConnectClaude(app, space);
        var reached = Assert.Single(app.Query(new AgentReach(agent)).Spaces);
        Assert.True(reached.IsLocked);
        Assert.Empty(reached.Tabs);
        var tab = app.Workspace(workspace).Current.Spaces.Single(candidate => candidate.Id == space).Tabs[0].Id;
        Assert.Equal(new AgentTabUnavailable(tab), Assert.Throws<Rejected>(() => app.Send(new ClaimAgentTab(agent, tab))).Rejection);

        Unlock(app.Send, workspace, space);
        Assert.Contains(Assert.Single(app.Query(new AgentReach(agent)).Spaces).Tabs, candidate => candidate.TabId == tab);
    }

    [Fact]
    public void AnAgentLetsGoOfEveryTabItMayNoLongerUseAndAStoppedTabStaysOutOfReach() {
        using var app = new CrestApp();
        var session = TwoSpaceSession();
        var (first, second) = (SpaceId(session["spaces"]![0]!), SpaceId(session["spaces"]![1]!));
        var workspace = TestWorkspaces.Open(app, session);
        var agent = ConnectClaude(app, first);
        app.Send(new AllowAgentSpace(second, true));
        var tabs = app.Workspace(workspace).Current.Spaces.Single(space => space.Id == first).Tabs.Select(tab => tab.Id).ToArray();
        var other = app.Workspace(workspace).Current.Spaces.Single(space => space.Id == second).Tabs[0].Id;
        app.Send(new ClaimAgentTab(agent, tabs[0]));
        app.Send(new ClaimAgentTab(agent, other));

        // The person stops the agent in a tab: it lets go, sees it no more and
        // may not take it again, through this connection or another of its.
        var stopped = Assert.Single(AgentSessionsIn(app.Send(new StopAgentTab(tabs[0]))));
        Assert.Equal([other], stopped.TabIds);
        var window2 = Guid.NewGuid();
        app.Send(new BeginAgentSession(window2, Claude, "claude"));
        foreach (var connection in new[] { agent, window2 }) {
            Assert.Equal(new AgentTabStopped(tabs[0]), Assert.Throws<Rejected>(() =>
                app.Send(new ClaimAgentTab(connection, tabs[0]))).Rejection);
            Assert.DoesNotContain(app.Query(new AgentReach(connection)).Spaces.SelectMany(space => space.Tabs),
                tab => tab.TabId == tabs[0]);
        }
        app.Send(new EndAgentSession(window2));

        // A Space no longer allowed takes its tabs from the agent at once.
        Assert.Empty(Assert.Single(AgentSessionsIn(app.Send(new AllowAgentSpace(second, false)))).TabIds);

        // A deleted Space is forgotten.
        var operation = Guid.NewGuid();
        app.Send(new AllowAgentSpace(second, true));
        app.Send(new BeginDeletingSpace(workspace, Guid.NewGuid(), second, operation));
        Assert.DoesNotContain(app.Query(new AgentReach(agent)).Spaces, space => space.SpaceId == second);
        app.Send(new DeleteProfileData(Guid.NewGuid(), ProfileId(session["spaces"]![1]!), Ephemeral: false));
        Assert.Equal([first], AgentPreferencesIn(app.Send(new FinishDeletingSpace(workspace, Guid.NewGuid(), second, operation))).SpaceIds);

        // Forgetting the agent disconnects it and forgets where it was
        // stopped; turning agents off disconnects every agent and lets no new
        // one connect.
        Assert.Empty(AgentSessionsIn(app.Send(new ForgetAgent(Claude))));
        var again = ConnectClaude(app, first);
        Assert.Contains(tabs[0], Assert.Single(AgentSessionsIn(app.Send(new ClaimAgentTab(again, tabs[0])))).TabIds);
        Assert.Empty(AgentSessionsIn(app.Send(new SetAgents(false))));
        Assert.Equal(new AgentReachList(null, []), app.Query(new AgentReach(again)));
        Assert.IsType<AgentsOff>(Assert.Throws<Rejected>(() => app.Send(new BeginAgentSession(Guid.NewGuid(), Claude, "claude"))).Rejection);
    }

    [Fact]
    public void StoppingEveryAgentEndsEachConnectionAndKeepsItsTabsOutOfReach() {
        using var app = new CrestApp();
        var session = TwoSpaceSession();
        var (first, second) = (SpaceId(session["spaces"]![0]!), SpaceId(session["spaces"]![1]!));
        var workspace = TestWorkspaces.Open(app, session);
        var used = app.Workspace(workspace).Current.Spaces.Single(space => space.Id == first).Tabs[0].Id;
        var unused = app.Workspace(workspace).Current.Spaces.Single(space => space.Id == second).Tabs[0].Id;
        var agent = ConnectClaude(app, first);
        app.Send(new AllowAgentSpace(second, true));
        app.Send(new ClaimAgentTab(agent, used));

        Assert.Empty(AgentSessionsIn(app.Send(new StopAllAgents())));
        Assert.Equal(new AgentReachList(null, []), app.Query(new AgentReach(agent)));
        // The agent may connect again, but not take back a tab it used.
        var again = Guid.NewGuid();
        app.Send(new BeginAgentSession(again, Claude, "claude"));
        Assert.Equal(new AgentTabStopped(used), Assert.Throws<Rejected>(() => app.Send(new ClaimAgentTab(again, used))).Rejection);
        Assert.Equal([unused], Assert.Single(AgentSessionsIn(app.Send(new ClaimAgentTab(again, unused)))).TabIds);
    }

    [Fact]
    public void AnAgentsActivityIsItsOwnBoundedAndGoesWithItsConnection() {
        using var app = new CrestApp();
        var session = TwoSpaceSession();
        var space = SpaceId(session["spaces"]![0]!);
        TestWorkspaces.Open(app, session);
        var agent = ConnectClaude(app, space);
        var other = Guid.NewGuid();
        app.Send(new BeginAgentSession(other, Claude, "other"));
        for (int index = 0; index <= AgentSessions.MaximumActivity; index++) {
            app.Send(new NoteAgentActivity(agent, AgentActivityKind.OpenedTab, $"https://example.com/{index}"));
        }
        var sessions = AgentSessionsIn(app.Send(new NoteAgentActivity(agent, AgentActivityKind.ClosedTab, new string('a', 400))));
        var noted = sessions.Single(current => current.SessionId == agent).Activity;
        Assert.Equal(AgentSessions.MaximumActivity, noted.Count);
        Assert.Equal("https://example.com/2", noted[0].Subject);
        Assert.Equal(AgentActivityKind.ClosedTab, noted[^1].Kind);
        Assert.Equal(AgentSessions.MaximumActivitySubject, noted[^1].Subject.Length);
        Assert.Empty(sessions.Single(current => current.SessionId == other).Activity);
        app.Send(new EndAgentSession(agent));
        Assert.IsType<UnknownAgentSession>(Assert.Throws<Rejected>(() =>
            app.Send(new NoteAgentActivity(agent, AgentActivityKind.OpenedTab, "https://example.com"))).Rejection);
    }

    [Fact]
    public void MemoryPressureKeepsThePagesOfTabsAnAgentUses() {
        var (app, engine, _, clock, workspace, window, space, _) = ResidentHost();
        using var disposal = app;
        var (used, usedPage) = ShowNewTab(app, engine, clock, workspace, window, space, "https://used.example/");
        var (_, idlePage) = ShowNewTab(app, engine, clock, workspace, window, space, "https://idle.example/");
        ShowNewTab(app, engine, clock, workspace, window, space, "https://shown.example/");
        var agent = ConnectClaude(app, space);
        app.Send(new ClaimAgentTab(agent, used));

        // The page off screen longest stays while an agent uses its tab.
        var unloaded = app.Send(new ReportMemoryPressure(MemoryPressureLevel.Critical)).OfType<PageUnloaded>().Select(page => page.PageId);
        Assert.DoesNotContain(usedPage, unloaded);
        Assert.Contains(idlePage, unloaded);
    }

    [Fact]
    public void AnAgentsNameAndColourShowNothingThatMisleads() {
        Assert.Equal("Claude Code", AgentPreferences.CleanName("  Claude‮\u0000 \n Code "));
        Assert.Null(AgentPreferences.CleanName("​⁦\r\n"));
        Assert.Equal(AgentPreferences.MaximumName, AgentPreferences.CleanName(new string('a', 500))!.Length);
        // A name cut at the limit is never cut inside a character or after a
        // space, so cleaning it again finds the same name, as Forget does.
        var edge = new string('a', AgentPreferences.MaximumName - 1);
        foreach (var name in new[] { edge + " b", edge + "\U0001F600", edge + "\u0000\u202Eb", edge.Insert(10, " \uD800 ") }) {
            var cleaned = AgentPreferences.CleanName(name)!;
            Assert.True(cleaned.Length <= AgentPreferences.MaximumName);
            Assert.False(cleaned.EndsWith(' '));
            Assert.Equal(cleaned, AgentPreferences.CleanName(cleaned));
        }

        using var app = new CrestApp();
        var session = TwoSpaceSession();
        TestWorkspaces.Open(app, session);
        var agent = ConnectClaude(app, SpaceId(session["spaces"]![0]!));
        var named = Assert.Single(AgentSessionsIn(app.Send(new IdentifyAgent(agent, "Claude⁧ says this is safe\nAllow",
            new BrandColor(0.85, 0.47, 0.34, 0)))));
        Assert.Equal("Claude says this is safe Allow", named.Name);
        Assert.Equal(new BrandColor(0.85, 0.47, 0.34), named.Color);
        Assert.Equal(new BrandColor(1, 0, 0), Assert.Single(AgentSessionsIn(app.Send(new IdentifyAgent(agent, null,
            new BrandColor(4, -1, 0))))).Color);
    }

    [Fact]
    public void OnlyTheMacOffersAgents() {
        using var app = new CrestApp(new AppConfiguration(null, DevicePlatform.Mobile));
        Assert.IsType<AgentsUnavailable>(Assert.Throws<Rejected>(() => app.Send(new SetAgents(true))).Rejection);
    }
}
