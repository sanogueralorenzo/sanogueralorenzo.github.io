using CrestCore.Domain;

namespace CrestCore.Contracts;

/// A provider a person searches with, as this device searches it: a built-in
/// with the options the person set for it, or one the person added. `Name`
/// spells which: a built-in's name, or `custom:` and the added provider's
/// identity, which is how a Space stores and syncs its choice. The palette
/// offers it to Tab after one of its `Shortcuts`, and its address and
/// suggestions render a query once into their placeholder.
public sealed record SearchProvider(string Name, string Title, SearchProviderKind Kind, IReadOnlyList<string> Shortcuts,
    string SearchTemplate, string? SuggestionTemplate, BrandColor Color, string? Logo, BuiltInSearchProvider? BuiltIn, Guid? CustomId) {
    #region Static Variables

    public const string CustomPrefix = "custom:";

    #endregion

    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<string> Shortcuts {
        get;
        init => field = [.. value];
    } = [.. Shortcuts];

    /// The host the provider searches, without `www.`, whose icon stands for
    /// a provider without a logo.
    [Resolved]
    public string Site => new SearchTemplate(SearchTemplate).Host;

    #endregion

    #region Actions - Lookup

    /// The name a provider a person added goes by.
    public static string CustomName(Guid id) => CustomPrefix + id.ToString("D");

    #endregion

    #region Actions - Searching

    /// The results address for `query`, percent-encoded as UTF-8 with only
    /// RFC 3986 unreserved characters left bare and written once into the
    /// placeholder, so a query that spells a placeholder stays text.
    public string Search(string query) => new SearchTemplate(SearchTemplate).Render(query);

    /// The suggestions address for `query`, or null when the provider offers none.
    public string? Suggest(string query) => SuggestionTemplate is { } template ? new SearchTemplate(template).Render(query) : null;

    /// Whether `word`, as typed, is one of the provider's shortcuts, which
    /// names it exactly enough to win Tab over a completion. Case never matters.
    internal bool HasShortcut(string word) => Shortcuts.Contains(Folded(word), StringComparer.Ordinal);

    /// How closely `word`, as typed, names the provider, lower being closer,
    /// or null when it does not: one of its shortcuts exactly, its title
    /// without spaces or its site exactly, then the start of a shortcut, of
    /// its title or of a word in it, or of its site. Case never matters.
    internal int? Closeness(string word) {
        string folded = Folded(word);
        if (folded.Length == 0) return null;
        string lowered = Title.ToLowerInvariant();
        string title = lowered.Replace(" ", "", StringComparison.Ordinal);
        string address = AddressWord(folded);
        if (HasShortcut(folded)) return 0;
        if (title == folded || Site.Length > 0 && Site == address) return 1;
        if (Shortcuts.Any(shortcut => shortcut.StartsWith(folded, StringComparison.Ordinal))) return 2;
        if (title.StartsWith(folded, StringComparison.Ordinal)) return 3;
        if (lowered.Split(' ', StringSplitOptions.RemoveEmptyEntries).Any(part => part.StartsWith(folded, StringComparison.Ordinal))) return 4;
        return Site.StartsWith(address, StringComparison.Ordinal) ? 5 : null;
    }

    /// Whether `word`, as typed, names the provider exactly: one of its
    /// shortcuts, its title without spaces or its site.
    internal bool IsNamedBy(string word) => Closeness(word) is <= 1;

    private static string Folded(string word) => word.Trim().ToLowerInvariant();

    /// A typed word read as a bare address: no scheme, no `www.`, no final slash.
    private static string AddressWord(string word) {
        int scheme = word.IndexOf("://", StringComparison.Ordinal);
        string bare = (scheme >= 0 ? word[(scheme + 3)..] : word).TrimEnd('/');
        return bare.StartsWith("www.", StringComparison.Ordinal) ? bare[4..] : bare;
    }

    #endregion

    #region Actions - Equality

    public bool Equals(SearchProvider? other) => other is not null
        && Name == other.Name
        && Title == other.Title
        && Kind == other.Kind
        && Shortcuts.SequenceEqual(other.Shortcuts)
        && SearchTemplate == other.SearchTemplate
        && SuggestionTemplate == other.SuggestionTemplate
        && Color == other.Color
        && Logo == other.Logo
        && BuiltIn == other.BuiltIn
        && CustomId == other.CustomId;

    public override int GetHashCode() => HashCode.Combine(Name, Title, Kind, Shortcuts.Count, SearchTemplate, SuggestionTemplate, Color,
        HashCode.Combine(Logo, BuiltIn, CustomId));

    #endregion
}
