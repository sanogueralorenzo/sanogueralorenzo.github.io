using CrestCore.Application;

namespace CrestCore.Contracts;

/// Returns every built-in provider to how it ships: on or off as it starts,
/// with its own shortcuts and no options set. The providers the person added,
/// the default search and suggestions stay.
public sealed record ResetSearchProviders() : SearchCatalogIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.ReviseSearchCatalog(turn.Changes, catalog => catalog.Reset());

    #endregion
}
