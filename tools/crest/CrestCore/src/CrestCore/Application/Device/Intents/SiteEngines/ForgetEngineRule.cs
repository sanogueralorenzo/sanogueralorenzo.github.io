using CrestCore.Application;

namespace CrestCore.Contracts;

/// Removes a persistent website rule so its new pages follow the default.
public sealed record ForgetEngineRule(SiteOrigin Origin) : Intent {
    #region Actions - Device

    internal override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.Device.ForgetEngineRule(Origin, changes));

    #endregion
}
