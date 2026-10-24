using CrestCore.Application;

namespace CrestCore.Contracts;

/// Removes the provider `Id` the person added. A default that was it becomes
/// Google; a Space that searches with it keeps searching with the copy it
/// carries.
public sealed record RemoveSearchProvider(Guid Id) : SearchCatalogIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) =>
        device.ReviseSearchCatalog(turn.Changes, catalog => catalog.Removing(Id));

    #endregion
}
