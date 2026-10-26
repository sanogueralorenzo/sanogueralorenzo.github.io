using CrestCore.Application;

namespace CrestCore.Contracts;

/// Keeps the device's search catalog for a device in `Language` and
/// `Region`, which automatic languages, regions and stores follow, and
/// publishes it, which is how a platform reads it from launch. The first time,
/// the device starts from the built-ins, adds the engines its Spaces carry,
/// makes what most of them chose the default and sets the Spaces that chose it
/// to follow the default. That first time waits until the session is no longer
/// the disposable seed a first launch made, so a platform sends this again
/// once the cloud's Spaces replaced the seed.
public sealed record RestoreSearchCatalog(string? Language, string? Region) : SearchCatalogIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) => device.RestoreSearchCatalog(turn.Changes, Language, Region);

    #endregion

    #region Actions - Routing

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(changes => {
        foreach (var follower in app.Device.RestoreSearchCatalog(changes, Language, Region))
            app.Device.Workspace(follower.WorkspaceId).Handle(
                new SetSpaceSearch(follower.WorkspaceId, follower.SpaceId, follower.Provider, follower.SuggestionsEnabled), app.Clock.Now, app.Ids,
                app.Pages);
    });

    #endregion
}
