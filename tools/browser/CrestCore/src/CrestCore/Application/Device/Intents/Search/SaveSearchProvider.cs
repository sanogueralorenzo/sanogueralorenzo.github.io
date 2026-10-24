using CrestCore.Application;

namespace CrestCore.Contracts;

/// Saves `Provider` among the providers the person added, in place of the one
/// of its identity or after the others. Refused with `InvalidSearchEngine`,
/// `InvalidSearchShortcut`, `DuplicateSearchEngineName`,
/// `DuplicateSearchShortcut` or `SearchEngineLimitReached`.
public sealed record SaveSearchProvider(CustomSearchProvider Provider) : SearchCatalogIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseSearchCatalog(turn.Changes, catalog => catalog.Saving(Provider));

    #endregion
}
