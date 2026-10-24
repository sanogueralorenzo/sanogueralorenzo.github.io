using System.Globalization;

using CrestCore.Domain;

namespace CrestCore.Contracts;

/// A search provider a person added: what it is, what they call it, the
/// shortcuts that name it in the palette, its search address and optional
/// suggestions, each holding exactly one `%s` or `{searchTerms}` placeholder,
/// and the color its chip wears, or none for its icon's. The device's catalog
/// keeps it; a Space that searches with it also carries its name and
/// addresses, which is all an older release reads.
public sealed record CustomSearchProvider(Guid Id, string Name, string SearchUrlTemplate, string? SuggestionUrlTemplate,
    SearchProviderKind Kind, IReadOnlyList<string> Shortcuts, BrandColor? Color) {
    #region Static Variables

    public const int MaximumNameLength = 64;

    /// The longest shortcut, in characters.
    public const int MaximumShortcutLength = 32;

    /// The color a provider wears until its icon gives it one.
    private static readonly BrandColor Neutral = new(0.45, 0.48, 0.52);

    #endregion

    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<string> Shortcuts {
        get;
        init => field = [.. value];
    } = [.. Shortcuts];

    /// The provider as the device searches with it.
    internal SearchProvider Provider => new(SearchProvider.CustomName(Id), Name, Kind, Shortcuts, SearchUrlTemplate, SuggestionUrlTemplate,
        Color ?? Neutral, Logo: null, BuiltIn: null, CustomId: Id);

    #endregion

    #region Constructors

    /// A search engine as a Space carried it before providers had kinds,
    /// shortcuts or colors.
    internal static CustomSearchProvider Carried(Guid id, string name, string search, string? suggestions) =>
        new(id, name, search, suggestions, SearchProviderKind.Engine, [], Color: null);

    #endregion

    #region Actions - Validation

    /// This provider trimmed and checked: a name of at most
    /// `MaximumNameLength` characters, addresses a person may give a provider,
    /// shortcuts lowercased, each once, without spaces, slashes, colons or a
    /// leading `@`, and an opaque color. Throws `Rejected` naming the first
    /// flaw.
    public CustomSearchProvider Admitted() {
        if (Id == Guid.Empty) throw new Rejected(new InvalidSearchEngine(SearchEngineFlaw.InvalidIdentity));
        string name = Name.Trim();
        if (name.Length == 0) throw new Rejected(new InvalidSearchEngine(SearchEngineFlaw.EmptyName));
        if (new StringInfo(name).LengthInTextElements > MaximumNameLength) throw new Rejected(new InvalidSearchEngine(SearchEngineFlaw.NameTooLong));
        return this with {
            Name = name,
            SearchUrlTemplate = SearchTemplate.Admit(SearchUrlTemplate).Pattern,
            SuggestionUrlTemplate = SearchTemplate.AdmitOptional(SuggestionUrlTemplate)?.Pattern,
            Shortcuts = AdmittedShortcuts(Shortcuts),
            Color = Color is { } color ? color with { Alpha = 1 } : null
        };
    }

    /// `shortcuts` trimmed, lowercased and each kept once, the blank ones
    /// left out. Throws `Rejected` with `InvalidSearchShortcut` for one that
    /// is too long or has whitespace, a slash, a colon or a leading `@`.
    internal static IReadOnlyList<string> AdmittedShortcuts(IEnumerable<string> shortcuts) {
        List<string> admitted = [];
        foreach (string shortcut in shortcuts.Select(word => word.Trim().ToLowerInvariant()).Where(word => word.Length > 0)) {
            if (shortcut.Length > MaximumShortcutLength || shortcut.StartsWith('@')
                || shortcut.Any(character => char.IsWhiteSpace(character) || character is '/' or ':'))
                throw new Rejected(new InvalidSearchShortcut());
            if (!admitted.Contains(shortcut)) admitted.Add(shortcut);
        }
        return admitted;
    }

    #endregion

    #region Actions - Equality

    public bool Equals(CustomSearchProvider? other) => other is not null
        && Id == other.Id
        && Name == other.Name
        && SearchUrlTemplate == other.SearchUrlTemplate
        && SuggestionUrlTemplate == other.SuggestionUrlTemplate
        && Kind == other.Kind
        && Shortcuts.SequenceEqual(other.Shortcuts)
        && Color == other.Color;

    public override int GetHashCode() => HashCode.Combine(Id, Name, SearchUrlTemplate, SuggestionUrlTemplate, Kind, Shortcuts.Count, Color);

    #endregion
}
