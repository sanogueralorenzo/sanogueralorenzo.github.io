using CrestCore.Application;

namespace CrestCore.Contracts;

/// Shows the last of the window's recent tabs (see `RecentTabs`), the oldest
/// of up to five, recording its use as `ShowTab` does. A split is one item and
/// shows the page used last. Publishes nothing when there is no other item to
/// show.
public sealed record ShowLeastRecentTab(Guid WindowId) : WindowIntent {
    #region Actions - Device

    /// Shows the last recent item's focused tab the way `ShowTab` does.
    internal override void Apply(Device device, DeviceTurn turn) {
        var window = device.Opened(WindowId);
        var session = device.Workspace(window.WorkspaceId).Current;
        Guid spaceId;
        IReadOnlyList<RecentTabItem> items;
        lock (device.Gate) {
            spaceId = window.ShownSpaceId;
            items = Device.Available(session, spaceId) is { } space ? device.RecentItems(window, space) : [];
        }
        if (items.Count > 1) new ShowTab(WindowId, spaceId, items[^1].FocusedTabId).Apply(device, turn);
    }

    #endregion
}
