using CrestCore.Application;

namespace CrestCore.Contracts;

/// Stops a window showing a tab the session keeps, such as a saved page it
/// closes without closing the tab: the window shows the tab it showed before
/// in that Space, recording its use, or nothing. A window that no longer
/// shows the tab publishes nothing.
public sealed record DismissShownTab(Guid WindowId, Guid SpaceId, Guid TabId) : WindowIntent {
    #region Actions - Device

    /// The window returns to the tab it showed before, recording its use the
    /// way showing a tab does, or shows nothing in that Space.
    internal override void Apply(Device device, DeviceTurn turn) {
        var window = device.Opened(WindowId);
        var authority = device.Workspace(window.WorkspaceId);
        if (Device.Available(authority.Current, SpaceId) is not { } space) return;
        Guid? fallback;
        lock (device.Gate) {
            if (window.Tab(space.Id) != TabId) return;
            fallback = window.DismissalFallback(space.Id, TabId, space.Tabs.Select(tab => tab.Id).ToHashSet());
        }
        if (fallback is { } tabId && authority.Touch(space.Id, tabId, DateTimeOffset.UtcNow) is { } touched)
            Device.Publish(SessionChanges.Publish(window.WorkspaceId, touched.Previous, touched.Next), turn.Changes);
        var session = authority.Current;
        lock (device.Gate)
            Device.Publish(device.Changing([window], shown => shown.ShowTab(space.Id, fallback, moves: false), session), turn.Changes);
    }

    #endregion
}
