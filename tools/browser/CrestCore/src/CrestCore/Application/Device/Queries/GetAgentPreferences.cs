using CrestCore.Application;

namespace CrestCore.Contracts;

/// This device's agent preferences.
public sealed record GetAgentPreferences : Query<AgentPreferences> {
    #region Actions - Answering

    internal override AgentPreferences Answer(CrestApp app) => app.Device.Agents;

    #endregion
}
