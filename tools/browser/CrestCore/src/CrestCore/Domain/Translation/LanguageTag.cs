namespace CrestCore.Domain;

/// The language, script and region of a BCP 47 or Apple locale identifier.
/// Two identifiers name the same translation language when their language
/// codes and effective scripts agree; regions are aliases of one another.
public sealed record LanguageTag(string Language, string? Script, string? Region) {
    #region Variables

    /// CLDR likely scripts for languages with one usual script. A language
    /// without an entry compares only the scripts its identifiers spell out.
    private static readonly Dictionary<string, string> DefaultScripts = new(StringComparer.Ordinal) {
        ["af"] = "Latn",
        ["am"] = "Ethi",
        ["ar"] = "Arab",
        ["az"] = "Latn",
        ["be"] = "Cyrl",
        ["bg"] = "Cyrl",
        ["bn"] = "Beng",
        ["bs"] = "Latn",
        ["ca"] = "Latn",
        ["cs"] = "Latn",
        ["cy"] = "Latn",
        ["da"] = "Latn",
        ["de"] = "Latn",
        ["el"] = "Grek",
        ["en"] = "Latn",
        ["es"] = "Latn",
        ["et"] = "Latn",
        ["eu"] = "Latn",
        ["fa"] = "Arab",
        ["fi"] = "Latn",
        ["fil"] = "Latn",
        ["fr"] = "Latn",
        ["ga"] = "Latn",
        ["gl"] = "Latn",
        ["gu"] = "Gujr",
        ["ha"] = "Latn",
        ["he"] = "Hebr",
        ["hi"] = "Deva",
        ["hr"] = "Latn",
        ["hu"] = "Latn",
        ["hy"] = "Armn",
        ["id"] = "Latn",
        ["is"] = "Latn",
        ["it"] = "Latn",
        ["iw"] = "Hebr",
        ["ja"] = "Jpan",
        ["ka"] = "Geor",
        ["kk"] = "Cyrl",
        ["km"] = "Khmr",
        ["kn"] = "Knda",
        ["ko"] = "Kore",
        ["ky"] = "Cyrl",
        ["lo"] = "Laoo",
        ["lt"] = "Latn",
        ["lv"] = "Latn",
        ["mk"] = "Cyrl",
        ["ml"] = "Mlym",
        ["mn"] = "Cyrl",
        ["mr"] = "Deva",
        ["ms"] = "Latn",
        ["my"] = "Mymr",
        ["nb"] = "Latn",
        ["ne"] = "Deva",
        ["nl"] = "Latn",
        ["nn"] = "Latn",
        ["no"] = "Latn",
        ["pa"] = "Guru",
        ["pl"] = "Latn",
        ["ps"] = "Arab",
        ["pt"] = "Latn",
        ["ro"] = "Latn",
        ["ru"] = "Cyrl",
        ["sd"] = "Arab",
        ["si"] = "Sinh",
        ["sk"] = "Latn",
        ["sl"] = "Latn",
        ["sq"] = "Latn",
        ["sr"] = "Cyrl",
        ["sv"] = "Latn",
        ["sw"] = "Latn",
        ["ta"] = "Taml",
        ["te"] = "Telu",
        ["tg"] = "Cyrl",
        ["th"] = "Thai",
        ["tl"] = "Latn",
        ["tr"] = "Latn",
        ["uk"] = "Cyrl",
        ["ur"] = "Arab",
        ["uz"] = "Latn",
        ["vi"] = "Latn",
        ["yi"] = "Hebr",
        ["yue"] = "Hant",
        ["zh"] = "Hans",
        ["zu"] = "Latn"
    };

    /// CLDR likely scripts where a region selects another script.
    private static readonly Dictionary<(string Language, string Region), string> RegionalScripts = new() {
        [("az", "IR")] = "Arab",
        [("mn", "CN")] = "Mong",
        [("pa", "PK")] = "Arab",
        [("sd", "IN")] = "Deva",
        [("sr", "ME")] = "Latn",
        [("uz", "AF")] = "Arab",
        [("yue", "CN")] = "Hans",
        [("zh", "HK")] = "Hant",
        [("zh", "MO")] = "Hant",
        [("zh", "TW")] = "Hant"
    };

    public string? EffectiveScript => Script
        ?? (Region is { } region && RegionalScripts.TryGetValue((Language, region), out var regional) ? regional : null)
        ?? DefaultScripts.GetValueOrDefault(Language);

    #endregion

    #region Actions - Languages

    /// Reads the leading language, script and region subtags, accepting `-` or
    /// `_` separators in any case. Null when there is no language subtag.
    public static LanguageTag? Parse(string? identifier) {
        if (string.IsNullOrWhiteSpace(identifier)) return null;
        var parts = identifier.Trim().Split('-', '_');
        string language = parts[0];
        if (language.Length is < 2 or > 8 or 4 || !language.All(char.IsAsciiLetter)) return null;
        string? script = null, region = null;
        int index = 1;
        if (index < parts.Length && parts[index].Length == 4 && parts[index].All(char.IsAsciiLetter)) {
            script = char.ToUpperInvariant(parts[index][0]) + parts[index][1..].ToLowerInvariant();
            index++;
        }
        if (index < parts.Length && (parts[index].Length == 2 && parts[index].All(char.IsAsciiLetter)
            || parts[index].Length == 3 && parts[index].All(char.IsAsciiDigit)))
            region = parts[index].ToUpperInvariant();
        return new(language.ToLowerInvariant(), script, region);
    }

    public static bool Matches(string? left, string? right) =>
        Parse(left) is { } a && Parse(right) is { } b && a.Language == b.Language
        && string.Equals(a.EffectiveScript, b.EffectiveScript, StringComparison.Ordinal);

    #endregion
}
