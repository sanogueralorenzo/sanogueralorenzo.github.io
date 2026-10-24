using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether returning a saved or pinned tab to the address it belongs to would
/// change anything: the tab is away from that page, or its page in `WindowId`
/// is heading to another. Not for a tab that belongs nowhere or is not there.
public sealed record CanReturnToSavedAddress(Guid WorkspaceId, Guid WindowId, Guid SpaceId, Guid TabId)
    : Query<SavedAddressReturn> {
    #region Actions - Answering

    /// Whether returning the tab to its saved address changes anything: it is
    /// away from that page, or its page in the window is heading to another.
    /// A tab that belongs nowhere, is gone or lives in a locked Space does not.
    internal override SavedAddressReturn Answer(CrestApp app) {
        var workspace = app.Pages.Device.Workspace(WorkspaceId);
        if (workspace.Current.Spaces.FirstOrDefault(space => space.Id == SpaceId) is not { } space
            || workspace.IsLocked(space)
            || space.Tabs.FirstOrDefault(tab => tab.Id == TabId) is not { SavedAddress: { } saved } tab)
            return new(ChangesPage: false);
        if (tab.IsAwayFromSavedAddress) return new(ChangesPage: true);
        var heading = app.Pages.Showing(WorkspaceId, WindowId, tab.Id)?.PendingUrl;
        return new(ChangesPage: heading is { } pending && !new WebAddress(pending).IsSamePage(new WebAddress(saved)));
    }

    #endregion
}
