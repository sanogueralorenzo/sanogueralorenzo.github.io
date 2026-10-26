using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether a tab dragged out of a window may leave it for a window of its
/// own. `DraggedTabs` is the multi-selection the drag carries, or null when
/// it carries the one tab.
public sealed record CanTearOff(Guid WindowId, Guid SpaceId, Guid ProfileId, Guid TabId, IReadOnlyList<Guid>? DraggedTabs)
    : Query<TearOffPermission> {
    #region Actions - Answering

    /// Whether a dragged tab may leave its window: the window still shows the
    /// Space the drag started in, with the profile it had and not being
    /// deleted, the Space is unlocked and holds the tab, and the drag carries
    /// that tab alone.
    internal override TearOffPermission Answer(CrestApp app) {
        var window = app.Device.Opened(WindowId);
        var authority = app.Device.Workspace(window.WorkspaceId);
        var space = Device.Available(authority.Current, SpaceId);
        if (space is null || space.ProfileId != ProfileId) return Refused(TearOffRefusal.SpaceChanged);
        if (authority.IsLocked(space)) return Refused(TearOffRefusal.SpaceLocked);
        if (space.Tabs.All(tab => tab.Id != TabId)) return Refused(TearOffRefusal.TabGone);
        if (DraggedTabs is { } dragged && (dragged.Count != 1 || dragged[0] != TabId))
            return Refused(TearOffRefusal.SeveralTabs);
        return new(Allowed: true, Reason: null);

        static TearOffPermission Refused(TearOffRefusal reason) => new(Allowed: false, reason);
    }

    #endregion
}
