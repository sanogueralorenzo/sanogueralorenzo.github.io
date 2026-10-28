using CrestCore.Application;

namespace CrestCore.Contracts;

/// The tab "Split With Next Tab" adds to the split of the tab a window shows:
/// the first tab row after the row that holds it, in the same list of its
/// Space's sidebar (its section's top level, or its folder's inside), whose tab
/// is in no split, when the core would join it; or none.
public sealed record SplitJoinCandidate(Guid WindowId) : Query<SplitJoinCandidateTab> {
    #region Actions - Answering

    /// The tab "Split With Next Tab" adds to the split of the tab a window
    /// shows: the next free tab row in its sidebar list, when the core would
    /// join it.
    internal override SplitJoinCandidateTab Answer(CrestApp app) {
        var window = app.Device.Opened(WindowId);
        var authority = app.Device.Workspace(window.WorkspaceId);
        Guid spaceId;
        Guid? shown;
        lock (app.Device.Gate) {
            spaceId = window.ShownSpaceId;
            shown = window.Tab(spaceId);
        }
        if (Device.Available(authority.Current, spaceId) is not { } space || shown is not { } tabId
            || space.SplitCandidate(tabId) is not { } candidate) return new(TabId: null);
        var joining = new JoinSplit(window.WorkspaceId, WindowId, space.Id, candidate, tabId, Index: null);
        return new(Device.Refusal(authority, joining, app.Clock.Now, app.Pages) is null ? candidate : null);
    }

    #endregion
}
