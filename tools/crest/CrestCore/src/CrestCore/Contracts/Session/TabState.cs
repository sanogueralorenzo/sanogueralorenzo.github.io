using CrestCore.Domain;

namespace CrestCore.Contracts;

/// <summary>
/// A tab as its Space keeps it. A native view has <see cref="NativeContent"/> and no
/// <see cref="Url"/>; a Start Page has neither. <see cref="StoredIconMode"/> is null
/// for a tab that never chose how its icon is filled, which then follows its
/// <see cref="Symbol"/>. Favicon bytes, live pages and engine history are never part of it.
/// The core publishes the values it resolves from these fields beside them, so no
/// platform works them out again, and never stores them.
/// </summary>
[Observed]
public sealed record TabState(
    Guid Id,
    string Title,
    string? Url,
    NativeTabContent? NativeContent,
    string? SavedUrl,
    string Symbol,
    string? FaviconUrl,
    TabIconAccent? IconAccent,
    TabIconMode? StoredIconMode,
    TabPlacement Placement,
    Guid? FolderId,
    Guid? SplitGroupId,
    DateTimeOffset LastActivatedAt,
    DateTimeOffset? PositionModifiedAt,
    string? CustomTitle,
    DateTimeOffset? TitleModifiedAt,
    bool KeepsPageLoaded) {
    #region Variables

    /// <summary>How the tab's icon is filled: its stored mode, or for a tab written
    /// before modes were stored, or with a term this build cannot name, the one its
    /// symbol implies.</summary>
    [Resolved]
    public TabIconMode IconMode => StoredIconMode ?? TabIconMode.Inferred(Symbol);

    /// <summary>The name every tab surface shows: the person's rename, or the page's
    /// title when there is none. A blank rename, however it arrived, is none.</summary>
    [Resolved]
    public string DisplayTitle => string.IsNullOrWhiteSpace(CustomTitle) ? Title : CustomTitle.Trim();

    /// <summary>A saved or pinned tab shows a page other than the one it was saved at.
    /// A current tab belongs nowhere, so it is never away.</summary>
    [Resolved]
    public bool IsAwayFromSavedAddress => SavedAddress is { } saved && Url is { } url
        && !new WebAddress(url).IsSamePage(new WebAddress(saved));

    /// <summary>The icon follows the page, and the favicon the tab keeps was taken from
    /// the page it shows, so the page need not fetch it again once the platform holds
    /// the image.</summary>
    [Resolved]
    public bool PageIconIsCurrent => IconMode.FollowsPage && FaviconUrl is { } icon && Url is { } url
        && new WebAddress(icon).IsSamePage(new WebAddress(url));

    /// <summary>The address a saved or pinned tab belongs to: the one it was saved at,
    /// or the one it shows when it has none. A current tab has none.</summary>
    public string? SavedAddress => Placement.IsDurable ? SavedUrl ?? Url : null;

    /// <summary>What the tab's surface shows: the Start Page, its native view or its web
    /// page.</summary>
    [Resolved]
    public TabSurface Surface => TabSurface.Of(NativeContent, Url);

    /// <summary>The native view the tab shows, or null for a web page, a Start Page or a
    /// view another build added, which keeps its kind but has no member here.</summary>
    [Resolved]
    public NativeView? NativeView => NativeView.Named(NativeContent?.Kind);

    /// <summary>The tab is a Start Page: it shows neither a web page nor a native view,
    /// and no sidebar lists it.</summary>
    public bool IsStartPage => Surface == TabSurface.StartPage;

    #endregion

    #region Actions - Repair

    /// A new Start Page tab, last shown `now`.
    internal static TabState NewStartPage(Guid id, DateTimeOffset now) => new(id, TabKind.StartPage.Name, null, null, null,
        TabKind.StartPage.Symbol, null, null, null, TabPlacement.Current, null, null, now, null, null, null, false);

    /// The tab as repair keeps it: a blank rename is no rename, edit clocks
    /// are whole milliseconds, and a Start Page wears its own title and symbol.
    internal TabState Normalized() {
        var normalized = this with {
            CustomTitle = string.IsNullOrWhiteSpace(CustomTitle) ? null : CustomTitle.Trim(),
            PositionModifiedAt = PositionModifiedAt is { } position ? BrowserEditTimestamp.Normalize(position) : null,
            TitleModifiedAt = TitleModifiedAt is { } title ? BrowserEditTimestamp.Normalize(title) : null
        };
        return normalized.IsStartPage
            ? normalized with { Title = TabKind.StartPage.Name, Symbol = TabKind.StartPage.Symbol } : normalized;
    }

    #endregion
}
