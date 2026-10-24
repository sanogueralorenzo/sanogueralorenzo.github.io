using CrestCore.Application;

namespace CrestCore.Contracts;

/// Offers the built-in `Provider` to Tab in the palette or not. A Space or
/// the default that searches with it still does.
public sealed record SetSearchProviderEnabled(BuiltInSearchProvider Provider, bool IsEnabled) : SearchCatalogIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseSearchCatalog(turn.Changes, catalog => catalog.Enabling(Provider, IsEnabled));

    #endregion
}
