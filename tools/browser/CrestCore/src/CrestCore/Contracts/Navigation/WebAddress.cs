namespace CrestCore.Contracts;

/// A web page's address as a page, a person or a record spelled it. A page's
/// fragment only points within it, so two spellings that differ only there
/// name one page; an address that is not http or https compares as spelled.
public readonly record struct WebAddress(string Spelling) {
    #region Variables

    /// The address history keeps for the page: an http or https address
    /// without its fragment, or null for one history does not keep.
    public string? Normalized => Uri.TryCreate(Spelling, UriKind.Absolute, out var value)
        && WebScheme.Named(value.Scheme) is not null ? Spelling.Split('#', 2)[0] : null;

    /// The web origin a page at this address belongs to, with its host in
    /// ASCII, or null for an address that is not http or https.
    public SiteOrigin? Origin => Uri.TryCreate(Spelling, UriKind.Absolute, out var value) && WebScheme.Named(value.Scheme) is not null
        && value.IdnHost.Length > 0 ? new SiteOrigin(value.Scheme, value.IdnHost, value.Port) : null;

    /// Where an http or https address points: its host, a port other than the
    /// scheme's own, its path, "/" when it has none, and its query. Null for
    /// any other address.
    public string? Location => Uri.TryCreate(Spelling, UriKind.Absolute, out var value) && WebScheme.Named(value.Scheme) is not null
        ? value.GetComponents(UriComponents.Host | UriComponents.Port | UriComponents.PathAndQuery, UriFormat.UriEscaped) : null;

    /// Whether the address shows a web page, or a blank one, rather than one
    /// of the browser's own, an extension's or a file.
    public bool IsWebPage => Normalized is not null || Spelling == "about:blank";

    #endregion

    #region Actions - Comparison

    /// Whether both addresses name one page. Everything that asks "is this
    /// still the page I captured?", such as a favicon or a saved address,
    /// asks it here, so a fragment or a scheme history does not keep cannot
    /// make one page look like two.
    public bool IsSamePage(WebAddress other) => (Normalized ?? Spelling) == (other.Normalized ?? other.Spelling);

    /// Whether this http or https address is the one `schemeless`, an
    /// address spelled without its scheme, names when read with this
    /// address's own scheme, ignoring case. A port it spells must be this
    /// address's port; with none, the scheme's own is.
    public bool IsAt(string schemeless) => Uri.TryCreate(Spelling, UriKind.Absolute, out var value)
        && WebScheme.Named(value.Scheme) is not null
        && string.Equals(Location, new WebAddress($"{value.Scheme}://{schemeless}").Location, StringComparison.OrdinalIgnoreCase);

    #endregion
}
