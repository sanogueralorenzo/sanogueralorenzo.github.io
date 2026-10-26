using CrestCore.Application;

namespace CrestCore.Contracts;

/// Persistent engine preferences, including a choice unavailable in this
/// composition. Private engine choices never enter this answer.
public sealed record GetEnginePreferences : Query<EnginePreferences> {
    #region Actions - Answering

    internal override EnginePreferences Answer(CrestApp app) => app.Device.EnginePreferences;

    #endregion
}
