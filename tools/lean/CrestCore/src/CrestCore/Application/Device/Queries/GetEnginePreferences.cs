using CrestCore.Application;

namespace CrestCore.Contracts;

/// The global engine preference, including a choice unavailable in this composition.
public sealed record GetEnginePreferences : Query<EnginePreferences> {
    #region Actions - Answering

    internal override EnginePreferences Answer(CrestApp app) => app.Device.EnginePreferences;

    #endregion
}
