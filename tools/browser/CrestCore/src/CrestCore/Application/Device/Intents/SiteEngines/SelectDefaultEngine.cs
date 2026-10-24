using CrestCore.Application;

namespace CrestCore.Contracts;

/// Chooses the engine new pages use on this device; null restores the
/// composition's default. Existing pages keep their engines.
public sealed record SelectDefaultEngine(EngineKind? Engine) : Intent {
    #region Actions - Device

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(changes => {
        if (Engine is not null && app.Engines.Registered(Engine) is null) throw new Rejected(new UnregisteredEngine(Engine));
        app.Device.PreferEngine(Engine, changes);
        app.Engines.Prefer(Engine);
        app.PublishEngines(changes.Publish);
    });

    #endregion
}
