namespace CrestCore.Contracts;

/// A site that keeps data in a profile, named as the engines group it: by its
/// registrable domain, such as `example.com` for `www.example.com`, or by its
/// host when it has none, such as `localhost`. `Kinds` lists what it keeps, in
/// `WebsiteDataKind.All` order.
public sealed record StoredSite(string Site, IReadOnlyList<WebsiteDataKind> Kinds) {
    #region Actions - Matching

    /// Whether the site is `host`'s own: the host itself or a domain it is under.
    internal bool Covers(string host) =>
        string.Equals(host, Site, StringComparison.OrdinalIgnoreCase)
        || host.EndsWith("." + Site, StringComparison.OrdinalIgnoreCase);

    /// The site keeping `kinds` too, such as another engine lists for it, in
    /// `WebsiteDataKind.All` order.
    internal StoredSite Keeping(IReadOnlyList<WebsiteDataKind> kinds) =>
        this with { Kinds = [.. WebsiteDataKind.All.Where(kind => Kinds.Contains(kind) || kinds.Contains(kind))] };

    #endregion
}
