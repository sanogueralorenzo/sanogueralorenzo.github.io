using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A sign a person types before a word to name what the palette narrows to:
/// `$` before a search provider's shortcut or name, or `@` before a scope's
/// keyword. The sign says what the person meant, so a space after a word that
/// names one enters it at once, without waiting for Tab, and what follows the
/// space becomes what is typed.
internal sealed class PaletteNotation {
    #region Static Variables

    public static readonly PaletteNotation Provider = new(sign: '$', entering: (context, word, text) =>
        context.Preferences.SearchesSitesWithTab && context.Catalog.NamedBy(word) is { } provider ? new(provider, null, text) : null);
    public static readonly PaletteNotation Scope = new(sign: '@', entering: (context, word, text) =>
        context.Preferences.Offers(PaletteSource.Scopes) && PaletteScope.Keyed($"@{word}") is { } scope
            && context.Preferences.Offers(scope.Source)
            ? new(null, scope, text) : null);

    public static IReadOnlyList<PaletteNotation> All { get; } = [Provider, Scope];

    #endregion

    #region Variables

    /// What a person types before the word.
    public char Sign { get; }

    /// What the word names, given what follows the space, or null when it
    /// names nothing the palette offers.
    private readonly Func<PaletteContext, string, string, PaletteEntry?> entering;

    #endregion

    #region Constructors

    private PaletteNotation(char sign, Func<PaletteContext, string, string, PaletteEntry?> entering) {
        Sign = sign;
        this.entering = entering;
    }

    #endregion

    #region Actions - Reading

    /// What `typed` enters: a sign, a word that names what its notation
    /// narrows to, then a space and whatever follows; null for anything else.
    public static PaletteEntry? Entry(PaletteContext context, string typed) {
        ArgumentNullException.ThrowIfNull(typed);
        string text = typed.TrimStart();
        int space = text.IndexOfAny([' ', '\t', ' ']);
        if (space < 2 || All.FirstOrDefault(notation => notation.Sign == text[0]) is not { } notation) return null;
        return notation.entering(context, text[1..space], text[(space + 1)..].TrimStart());
    }

    /// The word `text` names in this notation without its sign, or `text`
    /// as typed when it does not start with the sign.
    public string Word(string text) => text.Length > 1 && text[0] == Sign ? text[1..] : text;

    #endregion
}
