namespace CrestCore.Contracts;

/// Where a link activation goes: in place, into Peek, or into a new tab. A
/// decision is spelled as its `Name`. Engines keep ownership of request
/// security, downloads, form submissions and rendering. A decision travels
/// as its index in `All`, so `All` is append-only.
public sealed class LinkNavigationDecision {
    #region Variables

    public static readonly LinkNavigationDecision Navigate = new(name: "navigate");
    public static readonly LinkNavigationDecision PeekModifier = new(name: "peekModifier", opensPeek: true, stagesLink: true);
    public static readonly LinkNavigationDecision PeekSavedSite = new(name: "peekSavedSite", opensPeek: true, protectsSavedSite: true);
    public static readonly LinkNavigationDecision BackgroundTab = new(name: "backgroundTab", opensTab: true);
    public static readonly LinkNavigationDecision ForegroundTab = new(name: "foregroundTab", opensTab: true, selectsTab: true);

    public static IReadOnlyList<LinkNavigationDecision> All { get; } =
        [Navigate, PeekModifier, PeekSavedSite, BackgroundTab, ForegroundTab];

    public string Name { get; }

    /// The link opens in Peek instead of the page.
    public bool OpensPeek { get; }

    /// Peek opens because the link leaves a saved tab's site, not because the
    /// person asked for it.
    public bool ProtectsSavedSite { get; }

    /// The link opens in a new tab.
    public bool OpensTab { get; }

    /// The new tab is selected when it opens.
    public bool SelectsTab { get; }

    /// The link's request is staged before it leaves the page, so the Peek it
    /// opens keeps its initiator's referrer. A saved-site Peek starts afresh.
    public bool StagesLink { get; }

    #endregion

    #region Constructors

    private LinkNavigationDecision(string name, bool opensPeek = false, bool protectsSavedSite = false, bool opensTab = false,
        bool selectsTab = false, bool stagesLink = false) {
        Name = name;
        OpensPeek = opensPeek;
        ProtectsSavedSite = protectsSavedSite;
        OpensTab = opensTab;
        SelectsTab = selectsTab;
        StagesLink = stagesLink;
    }

    #endregion

    #region Actions - Lookup

    public static LinkNavigationDecision? Named(string? name) => All.FirstOrDefault(decision => decision.Name == name);

    #endregion

    #region Actions - Navigation

    /// Where following a link to `destination` goes, from the gesture, the
    /// person's link preferences and the tab's place and saved address.
    internal static LinkNavigationDecision For(string? destination, bool userActivatedLink,
        bool topLevel, bool peekModified, bool newTabModified, bool shiftModified,
        bool focusesNewTabs, bool hasContext, TabPlacement? placement, string? savedUrl,
        bool automaticallyOpensPeek) {
        if (!userActivatedLink || !TryWebUrl(destination, out var target)) return Navigate;
        if (topLevel && hasContext && peekModified) return PeekModifier;
        if (newTabModified)
            return focusesNewTabs != shiftModified ? ForegroundTab : BackgroundTab;
        if (topLevel && hasContext && automaticallyOpensPeek && placement?.IsDurable == true
            && TryWebUrl(savedUrl, out var saved) && NormalizeHost(saved!) != NormalizeHost(target!))
            return PeekSavedSite;
        return Navigate;
    }

    private static bool TryWebUrl(string? value, out Uri? url) =>
        Uri.TryCreate(value, UriKind.Absolute, out url)
        && WebScheme.Named(url.Scheme) is not null && url.Host.Length > 0;

    // Match Crest's saved-site contract: ignore www, but keep other subdomains
    // distinct. IdnHost also compares Unicode and punycode URL spellings equally.
    private static string NormalizeHost(Uri url) => RememberedSite.WithoutWww(url.IdnHost.ToLowerInvariant());

    #endregion
}
