using CrestCore.Domain;

namespace CrestCore.Contracts;

/// One ordered rule that sends matching external links to a Space.
public sealed record LinkRoute(Guid Id, bool IsEnabled, LinkRouteMatch Match, string Pattern, Guid DestinationSpaceId) {
    #region Actions - Routing

    /// Whether the route's pattern matches `url`; an empty pattern never
    /// matches.
    internal bool Matches(string url) {
        string pattern = Pattern.Trim();
        if (pattern.Length == 0) return false;
        return Match.Matches(Normalized(url), pattern, Normalized);
    }

    private static string Normalized(string address) => new WebAddress(address).Normalized ?? address;

    #endregion
}
