using CrestCore.Application;

namespace CrestCore.Contracts;

/// Sets whether the device's default search suggests searches as a person
/// types, in every Space that follows the default. No private window asks
/// for suggestions.
public sealed record SetSearchSuggestions(bool Enabled) : SearchCatalogIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseSearchCatalog(turn.Changes, catalog => catalog.Suggesting(Enabled));

    #endregion
}
