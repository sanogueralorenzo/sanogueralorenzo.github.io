using CrestCore.Contracts;

namespace CrestCore.Application;

/// This device's agent preferences, which the device store keeps and never
/// syncs; the agents connected now, which the core keeps in memory only; and
/// what agents may reach. Only a platform that offers agents runs any of it.
internal sealed partial class Device {
    #region Variables

    private AgentPreferences agents = AgentPreferences.Off;
    private readonly AgentSessions agentSessions = new();

    internal AgentPreferences Agents {
        get {
            lock (gate) return agents;
        }
    }

    /// The tabs some agent uses, which keep their pages loaded and their place
    /// in their Space while it does.
    internal IReadOnlySet<Guid> AgentTabs {
        get {
            lock (gate) return agentSessions.HeldTabs;
        }
    }

    #endregion

    #region Actions - Agent intents

    /// Runs one agent intent, publishing what it changed.
    public void Handle(AgentIntent intent, DeviceTurn turn) {
        if (!platform.OffersAgents) throw new Rejected(new AgentsUnavailable());
        intent.Apply(this, turn);
    }

    /// Keeps the preferences `revise` makes of the device's own, and publishes
    /// them when they changed. Agents turned off disconnect, and an agent the
    /// person no longer allows does too.
    internal void ReviseAgents(ChangeFeed changes, Func<AgentPreferences, AgentPreferences> revise) {
        lock (gate) {
            var revised = revise(agents);
            if (revised.Equals(agents)) return;
            agents = revised;
            storage?.EnqueueDevice(Records());
            changes.Publish(new AgentPreferencesChanged(agents));
            if (agentSessions.End(session => !revised.IsOn || !revised.Approves(session.Identity)))
                changes.Publish(new AgentSessionsChanged([.. agentSessions.All]));
            // An agent forgotten, or every agent once agents are off, starts
            // over where the person stopped it.
            agentSessions.Unstop(identity => !revised.IsOn || !revised.Approves(identity));
        }
        PruneAgents(changes);
    }

    /// Forgets a deleted Space in the agent preferences.
    public void ForgetAgents(Guid spaceId, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(changes);
        ReviseAgents(changes, preferences => preferences.Forgetting(spaceId));
    }

    /// Connects an approved agent as `sessionId`. Refused with `AgentsOff`
    /// while agents are off and `AgentNotApproved` for one the person did not
    /// allow.
    internal void BeginAgentSession(ChangeFeed changes, Guid sessionId, AgentIdentity identity, string name) {
        lock (gate) {
            if (!agents.IsOn) throw new Rejected(new AgentsOff());
            if (!agents.Approves(identity)) throw new Rejected(new AgentNotApproved());
            var normalized = identity.Normalized();
            var shown = AgentPreferences.CleanName(name) ?? agents.Agents.First(agent => agent.Identity == normalized).Name;
            if (agentSessions.Begin(sessionId, normalized, shown)) changes.Publish(new AgentSessionsChanged([.. agentSessions.All]));
        }
    }

    /// Runs `revise` on the agents connected now, publishing them when it
    /// changed anything.
    internal void ReviseAgentSessions(ChangeFeed changes, Func<AgentSessions, bool> revise) {
        lock (gate) {
            if (revise(agentSessions)) changes.Publish(new AgentSessionsChanged([.. agentSessions.All]));
        }
    }

    /// The agent connected as `sessionId` uses `tabId` from now on. Refused
    /// with `AgentTabUnavailable` for a tab no Space it reaches holds, one in
    /// a locked Space, or one showing one of Crest's own views.
    internal void ClaimAgentTab(ChangeFeed changes, Guid sessionId, Guid tabId) {
        // The session's own locks are taken before the device's.
        if (ReachedSpaces() is not { } reached) throw new Rejected(new AgentsOff());
        var holding = reached.FirstOrDefault(entry => entry.Space.Tabs.Any(tab => tab.Id == tabId));
        if (holding.Space is null || holding.IsLocked || !OffersToAgents(holding.Space.Tabs.First(tab => tab.Id == tabId)))
            throw new Rejected(new AgentTabUnavailable(tabId));
        ReviseAgentSessions(changes, sessions => sessions.Claim(sessionId, tabId));
    }

    /// Lets each agent go of the tabs it may no longer use: tabs that closed,
    /// moved out of the Spaces it reaches, sit in a Space that locked or left
    /// the web for a browser or extension page, and every tab once agents are
    /// off. Runs after every turn, and costs nothing
    /// while no agent is connected.
    internal void PruneAgents(ChangeFeed changes) {
        lock (gate) {
            if (agentSessions.All.Count == 0) return;
        }
        var usable = (ReachedSpaces() ?? [])
            .Where(entry => !entry.IsLocked)
            .SelectMany(entry => entry.Space.Tabs.Where(OffersToAgents).Select(tab => tab.Id))
            .ToHashSet();
        ReviseAgentSessions(changes, sessions => sessions.Prune(usable.Contains));
    }

    #endregion

    #region Actions - Reach

    /// Whether agents may be allowed to reach `spaceId`: a Space of the
    /// person's own session that is not being deleted. Called without the
    /// device lock, since it reads the session.
    internal bool OffersToAgents(Guid spaceId) =>
        Persistent() is (_, var authority) && authority.Current.Space(spaceId) is not null && !authority.IsDeleting(spaceId);

    /// Whether an agent may use `tab`: one that shows a web page or none yet,
    /// never Crest's own view, a browser or extension page, or a file.
    private static bool OffersToAgents(TabState tab) =>
        tab.NativeContent is null && (tab.Url is null || new WebAddress(tab.Url).IsWebPage);

    /// What the agent connected as `sessionId` may reach now: nothing while
    /// agents are off or for a session the core does not know, and otherwise
    /// each allowed Space of the person's own session that is not being
    /// deleted, in the session's order, with the tabs it may use. Called
    /// without the device lock, since it reads the session.
    internal AgentReachList AgentReach(Guid sessionId) {
        AgentSessionState? session;
        IReadOnlySet<Guid> stopped;
        lock (gate) {
            session = agentSessions.Find(sessionId);
            stopped = session is null ? new HashSet<Guid>() : agentSessions.Stopped(session.Identity);
        }
        if (session is null || ReachedSpaces() is not { } reached || Persistent() is not (var workspaceId, _)) return new(null, []);
        var spaces = reached.Select(entry => new AgentSpace(entry.Space.Id, entry.Space.Settings.Name, entry.IsLocked,
            entry.IsLocked ? [] : [.. entry.Space.Tabs
                .Where(tab => OffersToAgents(tab) && !stopped.Contains(tab.Id))
                .Select(tab => new AgentTab(tab.Id, tab.DisplayTitle, tab.Url, tab.Placement, session.TabIds.Contains(tab.Id)))]));
        return new(workspaceId, [.. spaces]);
    }

    /// Whether some agent uses the tab `tabId`, whose page then stays loaded.
    internal bool HoldsForAgent(Guid tabId) {
        lock (gate) return agentSessions.All.Any(session => session.TabIds.Contains(tabId));
    }

    /// The Spaces agents reach now, each with whether this process may show
    /// it, or null while agents are off or the person's own session is not
    /// open. Called without the device lock.
    private IReadOnlyList<(SpaceState Space, bool IsLocked)>? ReachedSpaces() {
        var preferences = Agents;
        if (!preferences.IsOn || Persistent() is not (_, var authority)) return null;
        return [.. authority.Current.Spaces
            .Where(space => preferences.SpaceIds.Contains(space.Id) && !authority.IsDeleting(space.Id))
            .Select(space => (space, authority.IsLocked(space)))];
    }

    #endregion
}
