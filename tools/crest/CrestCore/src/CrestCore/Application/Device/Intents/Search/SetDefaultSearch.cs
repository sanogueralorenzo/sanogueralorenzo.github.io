using CrestCore.Application;

namespace CrestCore.Contracts;

/// Makes `Provider` the device's default search, which every Space that
/// follows the default searches with. Refused with `UnknownSearchEngine` for
/// a provider the device does not keep and `UnsuitableDefaultSearch` for a
/// website.
public sealed record SetDefaultSearch(SearchProvider Provider) : SearchCatalogIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseSearchCatalog(turn.Changes, catalog => catalog.Choosing(Provider));

    #endregion
}
