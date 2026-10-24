using CrestCore.Application;

namespace CrestCore.Contracts;

/// Shows the tab of the window's Space used most recently other than the one
/// it shows, recording its use as `ShowTab` does. Publishes nothing when the
/// window shows no tab or the Space holds no other.
public sealed record ShowMostRecentTab(Guid WindowId) : WindowIntent {
    #region Actions - Device

    /// Shows the tab of the window's Space used most recently other than the
    /// one it shows, the way `ShowTab` does.
    internal override void Apply(Device device, DeviceTurn turn) {
        var window = device.Opened(WindowId);
        var session = device.Workspace(window.WorkspaceId).Current;
        Guid spaceId;
        Guid? shown;
        lock (device.Gate) {
            spaceId = window.ShownSpaceId;
            shown = window.Tab(spaceId);
        }
        if (Device.Available(session, spaceId) is not { } space || shown is not { } tabId
            || space.Tabs.Where(tab => tab.Id != tabId).MaxBy(tab => tab.LastActivatedAt) is not { } recent) return;
        new ShowTab(WindowId, space.Id, recent.Id).Apply(device, turn);
    }

    #endregion
}
