using CrestCore.Application;

namespace CrestCore.Contracts;

/// Sets `Option` of the built-in `Provider` to `Value`, or back to its default
/// when `Value` is blank. Refused with `UnknownSearchOption` for an option the
/// provider lacks or a value the option refuses.
public sealed record SetSearchOption(BuiltInSearchProvider Provider, SearchProviderOption Option, string? Value) : SearchCatalogIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseSearchCatalog(turn.Changes, catalog => catalog.Setting(Provider, Option, Value));

    #endregion
}
