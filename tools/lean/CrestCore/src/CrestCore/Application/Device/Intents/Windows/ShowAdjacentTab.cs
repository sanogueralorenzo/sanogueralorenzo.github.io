using CrestCore.Application;

namespace CrestCore.Contracts;

/// Shows the tab one stop from the one a window shows, in the order its Space's
/// sidebar shows them (see `SidebarOutline.Stops`), wrapping at both ends. A
/// split is one stop, and stepping onto it shows its first tab. A shown tab the
/// sidebar hides in a collapsed folder or section steps from where it lives
/// there, and a shown Start Page from the ends. Records the tab's use as
/// `ShowTab` does. Publishes nothing when the window shows no tab, the Space
/// shows no stops, or the step leads back to the stop it shows.
public sealed record ShowAdjacentTab(Guid WindowId, AdjacentDirection Direction) : WindowIntent {
    #region Actions - Device

    /// Steps the window's tab through its Space's sidebar, showing the tab the
    /// step reaches the way `ShowTab` does.
    internal override void Apply(Device device, DeviceTurn turn) {
        var window = device.Opened(WindowId);
        var session = device.Workspace(window.WorkspaceId).Current;
        Guid spaceId;
        Guid? shown;
        lock (device.Gate) {
            spaceId = window.ShownSpaceId;
            shown = window.Tab(spaceId);
        }
        if (Device.Available(session, spaceId) is not { } space || shown is not { } tabId || space.Step(tabId, Direction) is not { } next)
            return;
        new ShowTab(WindowId, space.Id, next).Apply(device, turn);
    }

    #endregion
}
