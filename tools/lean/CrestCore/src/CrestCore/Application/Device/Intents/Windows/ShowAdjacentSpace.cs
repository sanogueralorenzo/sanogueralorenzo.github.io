using CrestCore.Application;

namespace CrestCore.Contracts;

/// Shows the Space before or after the one a window shows, among the Spaces it
/// may show in the session's order, which leaves out one being deleted,
/// wrapping at both ends, as `ShowSpace` shows it. Publishes nothing when the
/// window may show fewer than two Spaces.
public sealed record ShowAdjacentSpace(Guid WindowId, AdjacentDirection Direction) : WindowIntent {
    #region Actions - Device

    /// Steps the window through the Spaces it may show, showing the one the
    /// step reaches the way `ShowSpace` does.
    internal override void Apply(Device device, DeviceTurn turn) {
        var window = device.Opened(WindowId);
        var spaces = Window.Showable(device.Workspace(window.WorkspaceId).Current).ToList();
        int shown;
        lock (device.Gate) shown = spaces.FindIndex(space => space.Id == window.ShownSpaceId);
        if (spaces.Count < 2 || shown < 0) return;
        new ShowSpace(WindowId, spaces[Direction.From(shown, spaces.Count)].Id).Apply(device, turn);
    }

    #endregion
}
