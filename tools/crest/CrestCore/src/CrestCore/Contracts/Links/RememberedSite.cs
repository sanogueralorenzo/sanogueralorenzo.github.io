namespace CrestCore.Contracts;

/// The Space a Quick Window last opened a site in, which the next external
/// link to that site opens in when the preferences remember Spaces by site.
/// `Site` is the lowercased host without a leading `www.`: Crest's site
/// identity for a host, where a leading `www.` names the same site as the bare
/// host, while every other subdomain stays distinct.
public sealed record RememberedSite(string Site, Guid SpaceId) {
    #region Static Variables

    private const string WwwPrefix = "www.";

    #endregion

    #region Actions - Sites

    /// The key a Quick Window remembers its Space under: the lowercased host
    /// without a leading `www.`. Null for an address without a host.
    internal static string? SiteOf(string url) {
        if (!Uri.TryCreate(url, UriKind.Absolute, out var value) || string.IsNullOrEmpty(value.Host)) return null;
        return WithoutWww(value.Host.ToLowerInvariant());
    }

    /// The host without one leading `www.`. Case is left to the caller, which
    /// may have lowercased or IDN-encoded the host first.
    internal static string WithoutWww(string host)
        => host.StartsWith(WwwPrefix, StringComparison.Ordinal) ? host[WwwPrefix.Length..] : host;

    #endregion
}
