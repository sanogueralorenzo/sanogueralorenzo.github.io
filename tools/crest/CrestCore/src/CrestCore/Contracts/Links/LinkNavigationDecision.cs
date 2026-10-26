namespace CrestCore.Contracts;

public sealed class LinkNavigationDecision {
    #region Static Variables

    public static readonly LinkNavigationDecision Navigate = new(name: "navigate");
    public static readonly LinkNavigationDecision BackgroundTab = new(name: "backgroundTab", opensTab: true);
    public static readonly LinkNavigationDecision ForegroundTab = new(name: "foregroundTab", opensTab: true, selectsTab: true);

    public static IReadOnlyList<LinkNavigationDecision> All { get; } =
        [Navigate, BackgroundTab, ForegroundTab];

    #endregion

    #region Variables

    public string Name { get; }

    /// The link opens in a new tab.
    public bool OpensTab { get; }

    /// The new tab is selected when it opens.
    public bool SelectsTab { get; }

    #endregion

    #region Constructors

    private LinkNavigationDecision(string name, bool opensTab = false, bool selectsTab = false) {
        Name = name;
        OpensTab = opensTab;
        SelectsTab = selectsTab;
    }

    #endregion

    #region Actions - Lookup

    public static LinkNavigationDecision? Named(string? name) => All.FirstOrDefault(decision => decision.Name == name);

    #endregion

    #region Actions - Navigation

    /// Where following a link to `destination` goes, from the gesture, the
    /// tab's place and saved address.
    internal static LinkNavigationDecision For(string? destination, bool userActivatedLink,
        bool topLevel, bool previewModified, bool newTabModified, bool shiftModified,
        bool hasContext, TabPlacement? placement, string? savedUrl) {
        if (!userActivatedLink || !TryWebUrl(destination, out var target)) return Navigate;
        if (topLevel && hasContext && previewModified) return ForegroundTab;
        if (newTabModified)
            return shiftModified ? ForegroundTab : BackgroundTab;
        if (topLevel && hasContext && placement?.IsDurable == true
            && TryWebUrl(savedUrl, out var saved) && NormalizeHost(saved!) != NormalizeHost(target!))
            return ForegroundTab;
        return Navigate;
    }

    private static bool TryWebUrl(string? value, out Uri? url) =>
        Uri.TryCreate(value, UriKind.Absolute, out url)
        && WebScheme.Named(url.Scheme) is not null && url.Host.Length > 0;

    // Match Crest's saved-site contract: ignore www, but keep other subdomains
    // distinct. IdnHost also compares Unicode and punycode URL spellings equally.
    private static string NormalizeHost(Uri url) {
        var host = url.IdnHost.ToLowerInvariant();
        return host.StartsWith("www.", StringComparison.Ordinal) ? host[4..] : host;
    }

    #endregion
}
