using CrestCore.Application;

namespace CrestCore.Contracts;

public sealed record AgentReach(Guid SessionId) : Query<AgentReachList> {
    #region Actions - Answering

    internal override AgentReachList Answer(CrestApp app) => app.Device.AgentReach(SessionId);

    #endregion
}
