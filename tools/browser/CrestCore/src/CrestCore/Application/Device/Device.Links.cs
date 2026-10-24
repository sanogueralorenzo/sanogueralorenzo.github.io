using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// This device's link preferences, which the device store keeps and never
/// syncs, and where a link another app hands a window opens under them.
internal sealed partial class Device {
    #region Variables

    private LinkPreferences links = LinkPreferences.Default;
    internal LinkPreferences Links { get => links; set => links = value; }

    #endregion

    #region Actions - Link intents

    /// Runs one link intent, publishing the preferences when they changed.
    public void Handle(LinkIntent intent, DeviceTurn turn) => intent.Apply(this, turn);

    /// Keeps the preferences `revise` makes of the device's own, and publishes
    /// them when they changed.
    internal void ReviseLinks(ChangeFeed changes, Func<LinkPreferences, LinkPreferences> revise) {
        lock (gate) Revise(revise(links), changes);
    }

    /// Forgets a deleted Space in the link preferences: its routes, its
    /// choice as the external-link Space and the sites that remembered it.
    public void ForgetLinks(Guid spaceId, ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(changes);
        lock (gate) Revise(links.Forgetting(spaceId), changes);
    }

    /// Keeps `revised` and publishes it when it differs from the preferences
    /// the device holds. The caller holds the device lock.
    private void Revise(LinkPreferences revised, ChangeFeed changes) {
        if (revised.Equals(links)) return;
        links = revised;
        storage?.EnqueueDevice(Records());
        changes.Publish(new LinkPreferencesChanged(links));
    }

    #endregion

    #region Actions - Routing

    /// What following a link from a page does: a page for a tab reads the
    /// tab's place and saved address, a Peek brings the tabs it opens to the
    /// front, and the rest follows this device's link preferences.
    public LinkNavigationAnswer Answer(LinkNavigation question, Pages pages) {
        ArgumentNullException.ThrowIfNull(question);
        ArgumentNullException.ThrowIfNull(pages);
        LinkPreferences preferences;
        lock (gate) preferences = links;
        var gesture = question.Gesture;
        var (peek, newTab) = preferences.PeekModifier.Intent(gesture.Modifiers, gesture.MiddleClick);
        var page = pages.Hosted(question.PageId);
        var tab = page is { TabId: { } tabId }
            ? Attached(page.WorkspaceId)?.Current.Spaces.FirstOrDefault(space => space.Id == page.SpaceId)?.Tabs
                .FirstOrDefault(candidate => candidate.Id == tabId)
            : null;
        bool focuses = preferences.FocusesNewTabs || page is { TabId: null, Transient.OpensNewTabsInFront: true };
        return new(LinkNavigationDecision.For(question.Url, gesture.UserActivated, gesture.TopLevel, peek, newTab,
            gesture.Modifiers.HasFlag(ShortcutModifiers.Shift), focuses, hasContext: tab is not null, tab?.Placement,
            tab?.SavedAddress, preferences.OpensPeekAutomatically));
    }

    #endregion
}
