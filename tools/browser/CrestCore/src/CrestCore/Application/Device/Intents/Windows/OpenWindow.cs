using CrestCore.Application;

namespace CrestCore.Contracts;

/// Opens a window over a workspace attached to this device. A saved window
/// keeps its record in the device store across launches, and only a window
/// over the persistent session may be saved. A saved window with a record
/// shows what the record shows. A window without a record starts as
/// `CopyingWindowId` shows, or on the launch Space. When `RestoresTabs` is
/// false it keeps only that Space and shows no tab until one is chosen.
/// `ShowingTabs` then name the tab it shows in those Spaces, and
/// `ShowingSpaceId` the Space it opens on, keeping what it shows there.
/// A saved window opens in front of the others the next launch reopens.
/// Opening a window that is already open answers what it shows.
public sealed record OpenWindow(Guid WindowId, Guid WorkspaceId, bool Saved, Guid? CopyingWindowId, Guid? ShowingSpaceId,
    IReadOnlyList<ShownTab> ShowingTabs, bool RestoresTabs) : WindowIntent {
    #region Actions - Device

    internal override void Apply(Device device, DeviceTurn turn) {
        var authority = device.Workspace(WorkspaceId);
        var session = authority.Current;
        lock (device.Gate) {
            if (device.OpenWindows.TryGetValue(WindowId, out var existing)) {
                device.Publishing(existing, session);
                turn.Changes.Publish(new WindowChanged(device.PublishedWindows[existing.Id]));
                return;
            }
            if (Saved && WorkspaceId != device.PersistentWorkspace)
                throw new Rejected(new UnsavedWorkspace(WorkspaceId));
            var window = Saved && device.SavedWindows.TryGetValue(WindowId, out var record)
                ? Window.Restoring(record, WorkspaceId)
                : CopyingWindowId is { } copied && device.OpenWindows.TryGetValue(copied, out var source)
                    && source.WorkspaceId == WorkspaceId
                    ? Window.Copying(source, WindowId, Saved)
                    : Window.Launching(WindowId, WorkspaceId, Saved, session,
                        WorkspaceId == device.PersistentWorkspace ? device.LegacyShownTabs : new Dictionary<Guid, Guid>());
            if (!RestoresTabs) window.ForgetTabs();
            foreach (var shown in ShowingTabs) window.ShowTab(shown.SpaceId, shown.TabId, moves: false);
            if (ShowingSpaceId is { } showing && session.Spaces.Any(space => space.Id == showing)) window.MoveTo(showing);
            window.Repair(session);
            device.OpenWindows[window.Id] = window;
            if (Saved) device.Reopen(window.Id);
            turn.Changes.Publish(device.Publishing(window, session)!);
        }
    }

    #endregion
}
