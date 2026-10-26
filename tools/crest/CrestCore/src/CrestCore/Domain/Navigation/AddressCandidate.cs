using CrestCore.Contracts;

namespace CrestCore.Domain;

/// An http or https address a Space knows, taken apart once so completing
/// what a person types compares only strings. `Source` ranks where it came
/// from: an open tab over a pinned or saved one, and either over history.
public sealed class AddressCandidate {
    #region Static Variables

    /// The rank of an address history keeps.
    public const int HistorySource = 1;
    /// The rank of an address a pinned or saved tab shows or belongs to.
    public const int SavedTabSource = 2;
    /// The rank of an address an open tab shows.
    public const int OpenTabSource = 3;
    /// The most visits that raise a history address's rank.
    public const int MaximumCountedVisits = 20;

    #endregion

    #region Variables

    public string Url { get; }
    public int Source { get; }
    public DateTimeOffset Date { get; }
    public int Visits { get; }
    /// When history first saw the address, or null for a tab's.
    public DateTimeOffset? FirstVisited { get; }
    /// `http` or `https`.
    public string Scheme { get; }
    /// The host, with the port when the address names one.
    public string Authority { get; }
    public string FoldedAuthority { get; }
    public bool HasPort { get; }
    /// The path as spelled, which may be empty.
    public string Path { get; }
    /// The query and fragment as spelled, each with its leading `?` or `#`.
    public string Suffix { get; }

    #endregion

    #region Constructors

    private AddressCandidate(string url, int source, DateTimeOffset date, int visits, DateTimeOffset? firstVisited, string scheme,
        string authority, bool hasPort, string path, string suffix) {
        Url = url;
        Source = source;
        Date = date;
        Visits = Math.Min(MaximumCountedVisits, visits);
        FirstVisited = firstVisited;
        Scheme = scheme;
        Authority = authority;
        FoldedAuthority = authority.ToLowerInvariant();
        HasPort = hasPort;
        Path = path;
        Suffix = suffix;
    }

    #endregion

    #region Actions - Parsing

    /// The address taken apart, or null for one that is not http or https,
    /// names no host, or carries a user name or password.
    public static AddressCandidate? Of(string url, int source, DateTimeOffset date, int visits, DateTimeOffset? firstVisited = null) {
        ArgumentNullException.ThrowIfNull(url);
        if (!Uri.TryCreate(url, UriKind.Absolute, out _)) return null;
        int separator = url.IndexOf("://", StringComparison.Ordinal);
        if (separator <= 0) return null;
        string scheme = url[..separator].ToLowerInvariant();
        if (WebScheme.Named(scheme) is null) return null;
        string rest = url[(separator + 3)..];
        int authorityEnd = rest.IndexOfAny(['/', '?', '#']);
        string authority = authorityEnd < 0 ? rest : rest[..authorityEnd];
        if (authority.Length == 0 || authority.Contains('@')) return null;
        int portSeparator = authority.StartsWith('[') ? authority.IndexOf("]:", StringComparison.Ordinal) + 1 : authority.LastIndexOf(':');
        bool hasPort = portSeparator > 0 && portSeparator < authority.Length - 1;
        string host = portSeparator > 0 ? authority[..portSeparator] : authority;
        if (host.Length == 0 || host == "[]") return null;
        string remainder = authorityEnd < 0 ? "" : rest[authorityEnd..];
        int suffixStart = remainder.IndexOfAny(['?', '#']);
        string path = suffixStart < 0 ? remainder : remainder[..suffixStart];
        string suffix = suffixStart < 0 ? "" : remainder[suffixStart..];
        return new(url, source, date, visits, firstVisited, scheme, hasPort ? authority : host, hasPort, path, suffix);
    }

    #endregion

    #region Actions - Completion

    /// What completing `typed` with this address would leave, or null when it
    /// does not complete it. The host completes whole, without a `www.` the
    /// person did not type; once they type a path, it completes to the next
    /// `/`, or to the end of the address when no `/` follows.
    public AddressMatch? Completing(TypedAddress typed) {
        ArgumentNullException.ThrowIfNull(typed);
        if (typed.SchemePrefix.Length > 0 && typed.SchemePrefix != Scheme + "://") return null;
        if (typed.HasColon && typed.SchemePrefix.Length == 0 && !HasPort) return null;
        bool hidesWww = FoldedAuthority.StartsWith("www.", StringComparison.Ordinal)
            && !typed.Authority.StartsWith("www.", StringComparison.Ordinal);
        string shown = hidesWww ? Authority[4..] : Authority;
        string folded = hidesWww ? FoldedAuthority[4..] : FoldedAuthority;
        if (!folded.StartsWith(typed.Authority, StringComparison.Ordinal)) return null;
        string path = "";
        if (typed.Path is { } typedPath) {
            if (typed.Authority != folded || !Path.StartsWith(typedPath, StringComparison.Ordinal)) return null;
            int next = Path.IndexOf('/', typedPath.Length);
            path = next < 0 ? Path + Suffix : Path[..(next + 1)];
        }
        string text = typed.SchemePrefix + shown + path;
        if (text.Length < typed.Text.Length) return null;
        string opens = $"{Scheme}://{Authority}{(path.Length == 0 ? "/" : path)}";
        return new(this, text, opens, typed.Path is not null ? 3 : typed.Authority == folded ? 2 : 1);
    }

    #endregion
}
