namespace CrestCore.Contracts;

/// What clearing a Space's browsing data, or one site's, can remove. The core
/// clears the Space's history itself; each engine clears what it keeps for the
/// Space's profile in the categories it holds, its own record of visits
/// included. A category travels as its index in `All`, so `All` is
/// append-only.
public sealed class BrowsingDataCategory {
    #region Static Variables

    public static readonly BrowsingDataCategory History = new(name: "history", title: "History", clearsHistory: true);

    /// Cookies and everything sites stored, service workers included, but not
    /// the cache. Clearing a site's signs the person out of it.
    public static readonly BrowsingDataCategory SiteData = new(name: "siteData", title: "Cookies and Site Data",
        detail: "Signs you out of most sites.", clearSiteTitle: "Clear Cookies", clearedTitle: "Cookies Cleared",
        failedTitle: "Couldn’t Clear Cookies", symbol: "person.crop.circle.badge.xmark");

    public static readonly BrowsingDataCategory Cache = new(name: "cache", title: "Cached Images and Files",
        clearSiteTitle: "Clear Cache", clearedTitle: "Cache Cleared", failedTitle: "Couldn’t Clear Cache", symbol: "trash");

    public static IReadOnlyList<BrowsingDataCategory> All { get; } = [History, SiteData, Cache];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the clear browsing data settings call the category.
    [Localized]
    public string Title { get; }

    /// What clearing the category does beyond removing it, when that matters.
    [Localized]
    public string? Detail { get; }

    /// The action that clears the category for the site a page shows, or nil
    /// when one site's share cannot be cleared on its own.
    [Localized]
    public string? ClearSiteTitle { get; }

    /// What the window says once a site's share is cleared.
    [Localized]
    public string? ClearedTitle { get; }

    /// What the window says when an engine could not clear a site's share.
    [Localized]
    public string? FailedTitle { get; }

    /// The SF Symbol beside the site action.
    public string? Symbol { get; }

    /// Clearing the category removes the Space's history, which the core keeps.
    public bool ClearsHistory { get; }

    /// One site's share of the category can be cleared on its own.
    public bool ClearsBySite => ClearSiteTitle is not null;

    #endregion

    #region Constructors

    private BrowsingDataCategory(string name, string title, string? detail = null, string? clearSiteTitle = null,
        string? clearedTitle = null, string? failedTitle = null, string? symbol = null, bool clearsHistory = false) {
        Name = name;
        Title = title;
        Detail = detail;
        ClearSiteTitle = clearSiteTitle;
        ClearedTitle = clearedTitle;
        FailedTitle = failedTitle;
        Symbol = symbol;
        ClearsHistory = clearsHistory;
    }

    #endregion
}
