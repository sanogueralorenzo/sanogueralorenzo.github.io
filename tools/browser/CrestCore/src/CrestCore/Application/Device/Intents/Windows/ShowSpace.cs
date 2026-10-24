using CrestCore.Application;

namespace CrestCore.Contracts;

/// Shows a Space in a window, on the tab the window last showed there while
/// it still exists, or else on the Space's fallback tab. A Space that is gone
/// or being deleted publishes nothing.
public sealed record ShowSpace(Guid WindowId, Guid SpaceId) : WindowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        var window = device.Opened(WindowId);
        var session = device.Workspace(window.WorkspaceId).Current;
        if (Device.Available(session, SpaceId) is not { } space || window.ShownSpaceId == space.Id) return;
        lock (device.Gate) Device.Publish(device.Changing([window], shown => shown.ShowSpace(space), session), turn.Changes);
    }

    #endregion
}
