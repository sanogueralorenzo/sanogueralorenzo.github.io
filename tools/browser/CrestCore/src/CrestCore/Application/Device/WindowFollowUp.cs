namespace CrestCore.Application;

/// What a session command chose for the window that issued it to show next:
/// the Space to move to, the tab to show in each Space whose shown tab it
/// changed (null to show none), and the tabs it dismissed, which that window's
/// history forgets. The device applies it when the command commits; other
/// windows are only repaired.
internal sealed class WindowFollowUp(Window? window) {
    #region Variables

    private readonly Dictionary<Guid, Guid?> tabs = [];
    private readonly List<(Guid SpaceId, Guid TabId)> dismissed = [];

    /// The window that issued the command, as the command read it; null for a
    /// command issued without one.
    public Window? Window { get; } = window;
    public Guid? SpaceId { get; private set; }
    public IReadOnlyDictionary<Guid, Guid?> Tabs => tabs;
    public IReadOnlyList<(Guid SpaceId, Guid TabId)> Dismissed => dismissed;

    #endregion

    #region Actions - Choosing

    public WindowFollowUp ShowSpace(Guid spaceId) {
        SpaceId = spaceId;
        return this;
    }

    /// Shows `tabId` in `spaceId`. Nothing is chosen when the window already
    /// shows it, so an unrelated command leaves the window as it was.
    public WindowFollowUp ShowTab(Guid spaceId, Guid? tabId) {
        if (Window?.Tab(spaceId) == tabId) tabs.Remove(spaceId);
        else tabs[spaceId] = tabId;
        return this;
    }

    public WindowFollowUp Dismiss(Guid spaceId, Guid tabId) {
        dismissed.Add((spaceId, tabId));
        return this;
    }

    /// The tab to show in `spaceId` after `tabId` leaves it: see
    /// `Window.DismissalFallback`. Only a window that shows `tabId` there has
    /// one, and the dismissal is remembered for when the command commits.
    public Guid? FallbackAfterDismissing(Guid spaceId, Guid tabId, IReadOnlySet<Guid> available) {
        if (Window is not { } shown || shown.Tab(spaceId) != tabId) return null;
        Dismiss(spaceId, tabId);
        return shown.DismissalFallback(spaceId, tabId, available);
    }

    #endregion
}
