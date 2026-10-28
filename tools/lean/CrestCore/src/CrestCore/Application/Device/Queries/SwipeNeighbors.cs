using CrestCore.Application;

namespace CrestCore.Contracts;

/// The tabs a swipe reaches either way from the tab a window shows, without
/// leaving the Space it shows: card by card through a split, then on to the
/// nearest card of the next stop of its sidebar, and nothing past either end
/// (see `SidebarOutline.Swipe`). Both are null when the window shows no tab.
public sealed record SwipeNeighbors(Guid WindowId) : Query<SwipeNeighborTabs> {
    #region Actions - Answering

    /// The tabs a swipe back and on from the window's shown tab reaches.
    internal override SwipeNeighborTabs Answer(CrestApp app) {
        var window = app.Device.Opened(WindowId);
        var session = app.Device.Workspace(window.WorkspaceId).Current;
        Guid spaceId;
        Guid? shown;
        lock (app.Device.Gate) {
            spaceId = window.ShownSpaceId;
            shown = window.Tab(spaceId);
        }
        if (Device.Available(session, spaceId) is not { } space || shown is not { } tabId) return new(PreviousTabId: null, NextTabId: null);
        return new(space.Swipe(tabId, AdjacentDirection.Previous), space.Swipe(tabId, AdjacentDirection.Next));
    }

    #endregion
}
