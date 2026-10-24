using CrestCore.Application;

namespace CrestCore.Contracts;

/// Gives the built-in `Provider` the shortcuts that name it in the palette,
/// or its own when `Shortcuts` is null or holds none. Refused with
/// `InvalidSearchShortcut` or `DuplicateSearchShortcut`.
public sealed record SetSearchShortcuts(BuiltInSearchProvider Provider, IReadOnlyList<string>? Shortcuts) : SearchCatalogIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseSearchCatalog(turn.Changes, catalog => catalog.Naming(Provider, Shortcuts));

    #endregion
}
