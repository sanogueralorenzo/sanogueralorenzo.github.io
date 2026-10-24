using CrestCore.Application;

namespace CrestCore.Contracts;

/// Makes `Provider` the default search in private windows, which every
/// private window's Space that follows the default searches with. Refused
/// with `UnknownSearchEngine` for a provider the device does not keep and
/// `UnsuitableDefaultSearch` for a website.
public sealed record SetPrivateSearch(SearchProvider Provider) : SearchCatalogIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseSearchCatalog(turn.Changes, catalog => catalog.ChoosingPrivate(Provider));

    #endregion
}
