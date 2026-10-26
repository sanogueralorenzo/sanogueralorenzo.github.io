namespace CrestCore.Contracts;

/// How a route's pattern is compared with a link's normalized address.
///
/// Link preferences (`crest.link-preferences.v1`) and the route-editing
/// policies spell a match as its `Name`, so a name never changes. A match
/// travels as its index in `All`, so `All` is append-only.
public sealed class LinkRouteMatch {
    #region Variables

    /// The address holds the pattern as typed, ignoring case.
    public static readonly LinkRouteMatch Contains = new(name: "contains", title: "Contains",
        matches: (address, pattern, _) => address.Contains(pattern, StringComparison.OrdinalIgnoreCase));

    /// The address is the pattern once both are normalized, ignoring case. A
    /// pattern without a scheme, such as a bare host, is read with the
    /// address's own scheme, so `docs.google.com` is that site's root address
    /// on http or https, and a port it spells must match.
    public static readonly LinkRouteMatch Exact = new(name: "exact", title: "Is Exactly",
        matches: (address, pattern, normalize) => string.Equals(address, normalize(pattern), StringComparison.OrdinalIgnoreCase)
            || (!pattern.Contains("://", StringComparison.Ordinal) && new WebAddress(address).IsAt(pattern)));

    public static IReadOnlyList<LinkRouteMatch> All { get; } = [Contains, Exact];

    public string Name { get; }

    /// What the route editor calls the match.
    [Localized]
    public string Title { get; }

    private readonly Func<string, string, Func<string, string>, bool> matches;

    #endregion

    #region Constructors

    private LinkRouteMatch(string name, string title, Func<string, string, Func<string, string>, bool> matches) {
        Name = name;
        Title = title;
        this.matches = matches;
    }

    #endregion

    #region Actions - Lookup

    public static LinkRouteMatch? Named(string? name) => All.FirstOrDefault(match => match.Name == name);

    #endregion

    #region Actions - Matching

    /// Whether a link's normalized `address` matches a route's trimmed,
    /// non-empty `pattern`. `normalize` normalizes an address the way the
    /// link's address was.
    public bool Matches(string address, string pattern, Func<string, string> normalize) {
        ArgumentNullException.ThrowIfNull(address);
        ArgumentNullException.ThrowIfNull(pattern);
        ArgumentNullException.ThrowIfNull(normalize);
        return matches(address, pattern, normalize);
    }

    #endregion
}
