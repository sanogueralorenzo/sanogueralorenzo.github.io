using CrestCore.Application;

namespace CrestCore.Contracts;

/// Shows a tab in a window, switching the window to the tab's Space, and
/// records when the tab was last used, which current-tab cleanup reads. A
/// null tab leaves the Space showing nothing and the window where it is. A
/// Space or tab that is already gone publishes nothing.
public sealed record ShowTab(Guid WindowId, Guid SpaceId, Guid? TabId) : WindowIntent {
    #region Actions - Device

    /// Showing a tab records its use first, as its own change to the
    /// workspace, so cleanup never archives what a window just showed. A
    /// workspace that takes no edits records nothing and still shows it.
    internal override void Apply(Device device, DeviceTurn turn) {
        var window = device.Opened(WindowId);
        var authority = device.Workspace(window.WorkspaceId);
        if (Device.Available(authority.Current, SpaceId) is not { } space) return;
        if (TabId is { } tabId) {
            if (space.Tabs.All(tab => tab.Id != tabId)) return;
            if (authority.Touch(SpaceId, tabId, DateTimeOffset.UtcNow) is { } touched)
                Device.Publish(SessionChanges.Publish(window.WorkspaceId, touched.Previous, touched.Next), turn.Changes);
        }
        var session = authority.Current;
        lock (device.Gate)
            Device.Publish(device.Changing([window], shown => shown.ShowTab(SpaceId, TabId, moves: true), session), turn.Changes);
    }

    #endregion
}
