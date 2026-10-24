using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The icon an engine last reported for the document a page shows: the
/// address it was found at and the color the page's theme puts behind it.
/// The image bytes stay with the binding.
internal sealed record PageIcon(string Url, TabIconAccent? Accent);

/// What a page's engine reported at `At` that edits the Space the page lives
/// in. The workspace's session applies each as one revision, or, while a
/// transaction holds the session, once it ends, in the order they arrived.
internal abstract record PageEdit(Guid PageId, Guid SpaceId, DateTimeOffset At) {
    #region Abstract Methods

    /// The Space after the edit, stamped `now`, which is `At` as the session
    /// stores it, and the image it has the page's tab wear, or null when the
    /// tab it edits is gone.
    public abstract (SpaceState Space, SessionFaviconUpdate? Favicon)? Apply(SpaceState space, DateTimeOffset now);

    /// What the edit tells readers of `workspaceId` beyond the session's own
    /// changes.
    public abstract IEnumerable<Change> Announced(Guid workspaceId);

    #endregion

    #region Actions - Tabs

    /// The Space with its tab at `index` replaced by `tab`, or the same Space
    /// when the tab did not change. Every recorded navigation copies its
    /// Space's tabs here, once.
    protected static SpaceState Replacing(SpaceState space, int index, BrowserTab tab) {
        var state = tab.State;
        if (state == space.Tabs[index]) return space;
        return space with { Tabs = [.. space.Tabs.Select((existing, position) => position == index ? state : existing)] };
    }

    protected static int IndexOf(SpaceState space, Guid tabId) {
        for (var index = 0; index < space.Tabs.Count; index++)
            if (space.Tabs[index].Id == tabId) return index;
        return -1;
    }

    #endregion
}

/// A page's document finished loading at `Url`, titled `Title`. The page's tab,
/// when it has one, shows the address and title and wears the document's icon
/// when its icon follows the page; the Space's history holds a visit, which
/// takes `VisitId` when the address has no entry yet.
internal sealed record NavigationRecord(Guid PageId, Guid SpaceId, DateTimeOffset At, Guid? TabId, string Url, string Title,
    PageIcon? Icon, Guid VisitId) : PageEdit(PageId, SpaceId, At) {
    #region Actions - Editing

    public override (SpaceState Space, SessionFaviconUpdate? Favicon)? Apply(SpaceState space, DateTimeOffset now) {
        SessionFaviconUpdate? favicon = null;
        if (TabId is { } tabId) {
            var index = IndexOf(space, tabId);
            if (index < 0) return null;
            var tab = BrowserTab.Restore(space.Tabs[index]);
            tab.ObserveAppearance(Url, Title);
            // The icon belongs to the document, which now shows this address.
            if (Icon is { } icon && tab.WearPageIcon(Url, icon.Accent)) favicon = new(tabId, Adopts: true, PageId);
            space = Replacing(space, index, tab);
        }
        return (space with { History = HistoryEntryState.Visit(space.History, Url, Title, now, VisitId) ?? space.History }, favicon);
    }

    public override IEnumerable<Change> Announced(Guid workspaceId) => [new NavigationRecorded(PageId, workspaceId, SpaceId, TabId, Url)];

    #endregion
}

/// A page whose document is recorded at `Url` gave it the title `Title`
/// since. The page's tab, while it still shows that page, takes it, and so
/// does the address's history entry when `Visit`, without another visit.
internal sealed record TitleRecord(Guid PageId, Guid SpaceId, DateTimeOffset At, Guid? TabId, string Url, string Title, bool Visit)
    : PageEdit(PageId, SpaceId, At) {
    #region Actions - Editing

    public override (SpaceState Space, SessionFaviconUpdate? Favicon)? Apply(SpaceState space, DateTimeOffset now) {
        if (TabId is { } tabId) {
            var index = IndexOf(space, tabId);
            if (index < 0) return null;
            var tab = BrowserTab.Restore(space.Tabs[index]);
            // The tab may have been sent to another address since.
            if (tab.Url is { } shown && new WebAddress(shown).IsSamePage(new WebAddress(Url))) {
                tab.ObserveAppearance(url: null, Title);
                space = Replacing(space, index, tab);
            }
        }
        if (Visit && HistoryEntryState.Retitle(space.History, Url, Title) is { } history) space = space with { History = history };
        return (space, null);
    }

    public override IEnumerable<Change> Announced(Guid workspaceId) => [];

    #endregion
}

/// A page whose document is recorded reported an icon for it, which its tab
/// wears while it shows that page and its icon follows the page.
internal sealed record IconAdoption(Guid PageId, Guid SpaceId, DateTimeOffset At, Guid TabId, PageIcon Icon)
    : PageEdit(PageId, SpaceId, At) {
    #region Actions - Editing

    public override (SpaceState Space, SessionFaviconUpdate? Favicon)? Apply(SpaceState space, DateTimeOffset now) {
        var index = IndexOf(space, TabId);
        if (index < 0) return null;
        var tab = BrowserTab.Restore(space.Tabs[index]);
        if (tab.Url is not { } shown || !new WebAddress(shown).IsSamePage(new WebAddress(Icon.Url))
            || !tab.WearPageIcon(Icon.Url, Icon.Accent)) return (space, null);
        return (Replacing(space, index, tab), new(TabId, Adopts: true, PageId));
    }

    public override IEnumerable<Change> Announced(Guid workspaceId) => [];

    #endregion
}
