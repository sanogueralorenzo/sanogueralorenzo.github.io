using CrestCore.Application;

namespace CrestCore.Contracts;

/// New pages of `Origin` open on `Engine` from now on. A choice made in a
/// Space of the persistent session holds for every Space, and the device store
/// keeps it; past its limit, the least recently chosen site is forgotten. One
/// made in any other Space, such as a private one, holds for that Space alone
/// and lives as long as the process. Refused for an origin that is not valid,
/// a locked Space or an engine this device did not register.
public sealed record ChooseSiteEngine(Guid SpaceId, SiteOrigin Origin, EngineKind Engine) : Intent {
    #region Actions - Device

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(_ => {
        if (app.Engines.Registered(Engine) is null) throw new Rejected(new UnregisteredEngine(Engine));
        app.Device.Choose(SpaceId, Origin, Engine);
    });

    #endregion
}
