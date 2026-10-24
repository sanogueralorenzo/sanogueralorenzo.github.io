namespace CrestCore.Domain;

/// What a person typed, read as the start of an address: at least two
/// characters with no whitespace, query, fragment or user name, and when it
/// names a scheme, http or https.
public sealed class TypedAddress {
    #region Static Variables

    private const int MinimumLength = 2;
    private const int MaximumLength = 2_048;

    #endregion

    #region Variables

    public string Text { get; }
    public string Lowercased { get; }
    /// `http://` or `https://` when typed, else empty.
    public string SchemePrefix { get; }
    public bool HasColon { get; }
    /// The host and port typed so far, lowercased.
    public string Authority { get; }
    /// The path typed after the host, or null when no `/` was typed.
    public string? Path { get; }

    #endregion

    #region Constructors

    private TypedAddress(string text, string lowercased, string schemePrefix, string authority, string? path) {
        Text = text;
        Lowercased = lowercased;
        SchemePrefix = schemePrefix;
        HasColon = text.Contains(':');
        Authority = authority;
        Path = path;
    }

    #endregion

    #region Actions - Parsing

    /// The text read as the start of an address, or null when it cannot be one.
    public static TypedAddress? Of(string text) {
        ArgumentNullException.ThrowIfNull(text);
        if (text.Length < MinimumLength || text.Length > MaximumLength || text.Any(char.IsWhiteSpace)
            || text.Contains('?') || text.Contains('#') || text.Contains('@')) return null;
        string lowercased = text.ToLowerInvariant();
        string schemePrefix = "";
        if (text.Contains("://", StringComparison.Ordinal)) {
            if (lowercased.StartsWith("https://", StringComparison.Ordinal)) schemePrefix = "https://";
            else if (lowercased.StartsWith("http://", StringComparison.Ordinal)) schemePrefix = "http://";
            else return null;
        }
        string typed = text[schemePrefix.Length..];
        if (typed.Length < MinimumLength) return null;
        int slash = typed.IndexOf('/');
        string authority = slash < 0 ? typed : typed[..slash];
        return new(text, lowercased, schemePrefix, authority.ToLowerInvariant(), slash < 0 ? null : typed[slash..]);
    }

    #endregion
}
