using CrestCore.Application;

namespace CrestCore.Contracts;

/// What a window can switch between in the Space it shows: the tabs it showed
/// there since it opened, a split as one item, the shown item first (see
/// `Device.RecentItems`). Items are in memory only, so a window that has
/// shown nothing else lists its shown tab and the Space's tab used last.
public sealed record RecentTabs(Guid WindowId) : Query<RecentTabList> {
    #region Actions - Answering

    /// The items the window can switch between in the Space it shows.
    internal override RecentTabList Answer(CrestApp app) {
        var window = app.Device.Opened(WindowId);
        var session = app.Device.Workspace(window.WorkspaceId).Current;
        lock (app.Device.Gate)
            return new(Device.Available(session, window.ShownSpaceId) is { } space
                ? app.Device.RecentItems(window, space) : []);
    }

    #endregion
}
