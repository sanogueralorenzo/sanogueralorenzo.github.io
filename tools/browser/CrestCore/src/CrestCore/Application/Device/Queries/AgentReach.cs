using CrestCore.Application;

namespace CrestCore.Contracts;

/// What the agent connected as `SessionId` may reach now: nothing while agents
/// are off, and otherwise each Space the person allowed that their own session
/// holds and is not being deleted, in the session's order, with whether it is
/// locked and the tabs the agent may use in it. A private window's Spaces and
/// a borrowed workspace's are never reached.
public sealed record AgentReach(Guid SessionId) : Query<AgentReachList> {
    #region Actions - Answering

    internal override AgentReachList Answer(CrestApp app) => app.Device.AgentReach(SessionId);

    #endregion
}
