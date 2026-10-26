namespace CrestCore.Contracts;

#region Queries

/// What an agent's session may reach now. With agents off, or a session the
/// core does not know, there is no workspace and no Space. Otherwise
/// `WorkspaceId` is the person's own session, and `Spaces` lists each allowed
/// Space it holds that is not being deleted, in the session's order.
public sealed record AgentReachList(Guid? WorkspaceId, IReadOnlyList<AgentSpace> Spaces) {
    #region Actions - Equality

    public bool Equals(AgentReachList? other) =>
        other is not null && WorkspaceId == other.WorkspaceId && Spaces.SequenceEqual(other.Spaces);

    public override int GetHashCode() => HashCode.Combine(WorkspaceId, Spaces.Count);

    #endregion
}

/// A Space an agent may reach: its name, whether this process may show it,
/// and the tabs an agent may use in it, none while it is locked.
public sealed record AgentSpace(Guid SpaceId, string Name, bool IsLocked, IReadOnlyList<AgentTab> Tabs) {
    #region Actions - Equality

    public bool Equals(AgentSpace? other) => other is not null && SpaceId == other.SpaceId && Name == other.Name
        && IsLocked == other.IsLocked && Tabs.SequenceEqual(other.Tabs);

    public override int GetHashCode() => HashCode.Combine(SpaceId, Name, IsLocked, Tabs.Count);

    #endregion
}

/// A tab an agent may use: the name and address its Space shows, which section
/// it sits in, and whether the asking session already uses it. A tab showing
/// one of Crest's own views is never one.
public sealed record AgentTab(Guid TabId, string Title, string? Url, TabPlacement Placement, bool Claimed);

#endregion

#region Sessions

/// An agent connected now: who macOS says it is, the name and colour it goes
/// by, the tabs it uses, whether the person let it open windows without
/// asking each time, and what it did that changed the person's browser,
/// oldest first.
public sealed record AgentSessionState(Guid SessionId, AgentIdentity Identity, string Name, BrandColor? Color,
    IReadOnlyList<Guid> TabIds, bool OpensWindows, IReadOnlyList<AgentActivity> Activity) {
    #region Actions - Equality

    public bool Equals(AgentSessionState? other) => other is not null && SessionId == other.SessionId
        && Identity == other.Identity && Name == other.Name && Color == other.Color && TabIds.SequenceEqual(other.TabIds)
        && OpensWindows == other.OpensWindows && Activity.SequenceEqual(other.Activity);

    public override int GetHashCode() => HashCode.Combine(SessionId, Name, TabIds.Count);

    #endregion
}

/// One thing an agent did that changed the person's browser: what, what it
/// was about, such as an address or a tab's name, and when.
public sealed record AgentActivity(AgentActivityKind Kind, string Subject, DateTimeOffset At);

#endregion

#region Changes

/// This device's agent preferences changed.
public sealed record AgentPreferencesChanged(AgentPreferences Preferences) : Change;

/// The agents connected now, or the tabs they use, changed.
public sealed record AgentSessionsChanged(IReadOnlyList<AgentSessionState> Sessions) : Change {
    #region Actions - Equality

    public bool Equals(AgentSessionsChanged? other) => other is not null && Sessions.SequenceEqual(other.Sessions);

    public override int GetHashCode() => Sessions.Count;

    #endregion
}

#endregion

#region Rejections

/// This device offers no agents: only the Mac does.
public sealed record AgentsUnavailable : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Agents can’t use Crest on this device.";

    #endregion
}

/// The person has agents turned off.
public sealed record AgentsOff : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Agents are turned off in Crest’s settings.";

    #endregion
}

/// The person has not allowed this agent.
public sealed record AgentNotApproved : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "The person hasn’t allowed this agent to use Crest.";

    #endregion
}

/// No agent is connected as `SessionId`.
public sealed record UnknownAgentSession(Guid SessionId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "This agent is no longer connected to Crest.";

    #endregion
}

/// Only a Space of the person's own session that they allow agents to reach
/// may be: never a private window's, a borrowed workspace's, or one being
/// deleted.
public sealed record AgentSpaceUnavailable(Guid SpaceId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "That Space isn’t one agents may use.";

    #endregion
}

/// The tab is not one an agent may use: it is in no Space the agent reaches,
/// shows one of Crest's own views, or sits in a locked Space.
public sealed record AgentTabUnavailable(Guid TabId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "That tab isn’t one agents may use.";

    #endregion
}

/// The person stopped this agent from using the tab.
public sealed record AgentTabStopped(Guid TabId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "The person stopped agents from using this tab.";

    #endregion
}

/// An agent's identity names no program, or its name has nothing to show
/// within `MaximumName` characters.
public sealed record InvalidAgent(int MaximumName) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Crest couldn’t tell which program this agent is.";

    #endregion
}

/// No agent more can be allowed: there are already `Maximum`.
public sealed record AgentsFull(int Maximum) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Too many agents are allowed. Forget one in Settings first.";

    #endregion
}

/// No agent more can connect at once: there are already `Maximum`.
public sealed record AgentSessionsFull(int Maximum) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Too many agents are using Crest right now.";

    #endregion
}

#endregion
