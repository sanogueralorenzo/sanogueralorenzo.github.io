using System.Text;

namespace CrestCore.Generator;

/// Spellings the generated sources derive from C# names.
internal static class Naming {
    #region Variables

    private static readonly HashSet<string> SwiftKeywords = new(StringComparer.Ordinal) {
        "associatedtype", "class", "deinit", "default", "enum", "extension", "func", "import", "init", "inout",
        "internal", "let", "operator", "private", "protocol", "public", "static", "struct", "subscript",
        "typealias", "var", "break", "case", "continue", "do", "else", "fallthrough", "for", "guard", "if",
        "in", "repeat", "return", "switch", "where", "while", "as", "catch", "false", "is", "nil", "rethrows",
        "super", "self", "Self", "throw", "throws", "true", "try", "Type", "Protocol"
    };

    /// Words Swift spells as initialisms, keyed by their C# spelling.
    private static readonly Dictionary<string, string> Initialisms = new(StringComparer.Ordinal) {
        ["Id"] = "ID",
        ["Ids"] = "IDs",
        ["Url"] = "URL",
        ["Urls"] = "URLs"
    };

    #endregion

    #region Actions - Swift

    /// A property or case name: lowerCamel with `Id` as `ID` and `Url` as `URL`
    /// (`ProfileId` becomes `profileID`, `Id` becomes `id`).
    public static string SwiftMember(string name) {
        var words = Words(name);
        var result = new StringBuilder(words[0].ToLowerInvariant());
        foreach (var word in words.Skip(1)) result.Append(Initialisms.TryGetValue(word, out var initialism) ? initialism : word);
        return result.ToString();
    }

    /// A Swift identifier, escaped when it is a keyword.
    public static string SwiftIdentifier(string name) => SwiftKeywords.Contains(name) ? $"`{name}`" : name;

    #endregion

    #region Actions - C

    /// `AcknowledgeDownloads` becomes `ACKNOWLEDGE_DOWNLOADS`.
    public static string UpperSnake(string name) => string.Join('_', Words(name).Select(word => word.ToUpperInvariant()));

    #endregion

    #region Actions - Words

    /// Splits a PascalCase name into words. A run of capitals is one word
    /// (`HTTPRequest` is `HTTP`, `Request`).
    public static IReadOnlyList<string> Words(string name) {
        ArgumentException.ThrowIfNullOrEmpty(name);
        var words = new List<string>();
        int start = 0;
        for (int index = 1; index < name.Length; index++) {
            bool upper = char.IsUpper(name[index]);
            bool previousUpper = char.IsUpper(name[index - 1]);
            bool nextLower = index + 1 < name.Length && char.IsLower(name[index + 1]);
            if (upper && (!previousUpper || nextLower)) {
                words.Add(name[start..index]);
                start = index;
            }
        }
        words.Add(name[start..]);
        return words;
    }

    #endregion
}
