namespace CrestCore.Contracts;

/// The live state of a page that rules and views read: what its engine last
/// showed (see `PageSnapshot`), and why its latest navigation failed. A
/// failure stays until another navigation commits a new document, or the
/// page is asked to load again or to leave the failure, so an engine that
/// retries on its own keeps showing it. A failure over the document the page
/// still shows lets the page go back to that document. Never saved or synced.
public sealed record PageLiveState(string? Url, string? PendingUrl, string Title, bool IsLoading, bool CanGoBack,
    bool CanGoForward, PageSecurity Security, PageFailure? Failure, PageMediaActivity Media) {
    #region Static Variables

    /// A page its engine has shown nothing in yet.
    public static PageLiveState Blank { get; } = new(Url: null, PendingUrl: null, Title: "", IsLoading: false, CanGoBack: false,
        CanGoForward: false, PageSecurity.None, Failure: null, PageMediaActivity.None);

    #endregion

    #region Variables

    /// The address the page shows the person: the one that failed, the one a
    /// navigation is heading to, or its document's own.
    [Resolved]
    public string? Address => Failure?.Url ?? PendingUrl ?? Url;

    #endregion
}
