using System.Globalization;
using System.Text;

using CrestCore.Domain;

namespace CrestCore.Contracts;

/// A password file to save as `FileName`: a Space's passwords as a browser
/// password file every browser and password manager reads, with a name, site,
/// username, password and note for each password, in order of site, then
/// username as a person sorts them, then identity. A password without a name
/// is named after its site's host. The file is named after the Space.
[HoldsSecrets]
public sealed record CredentialExportFile(string FileName, byte[] Contents) {
    #region Static Variables

    /// The columns the file names in its first row.
    private static readonly IReadOnlyList<string> Headers = ["name", "url", "username", "password", "note"];

    /// The most characters of the Space's name the file name keeps.
    private const int MaximumNameCharacters = 80;

    #endregion

    #region Actions - Exporting

    /// The file of `query`'s passwords.
    internal static CredentialExportFile Of(CredentialExport query) {
        ArgumentNullException.ThrowIfNull(query);
        var rows = query.Credentials
            .OrderBy(credential => credential.Origin.Spelling, StringComparer.Ordinal)
            .ThenBy(credential => credential.Username, Comparer<string>.Create(CompareUsernames))
            .ThenBy(credential => credential.Id.ToString("D"), StringComparer.Ordinal)
            .Select(credential => (IReadOnlyList<string>)[credential.DisplayName ?? credential.Origin.Host, credential.Origin.Spelling,
                credential.Username, credential.Password, credential.Note]);
        string text = CsvWriter.Write([Headers, .. rows]);
        return new(Named(query.SpaceName, query.FallbackName), Encoding.UTF8.GetBytes(text));
    }

    /// The file name for the Space named `spaceName`: its letters and digits,
    /// each run joined by one space and cut to 80 characters, or
    /// `fallbackName` when it has none.
    internal static string Named(string spaceName, string fallbackName) {
        ArgumentNullException.ThrowIfNull(spaceName);
        ArgumentNullException.ThrowIfNull(fallbackName);
        var words = new List<string>();
        var word = new StringBuilder();
        foreach (var rune in spaceName.EnumerateRunes()) {
            if (IsAlphanumeric(rune)) {
                word.Append(rune.ToString());
            } else if (word.Length > 0) {
                words.Add(word.ToString());
                word.Clear();
            }
        }
        if (word.Length > 0) words.Add(word.ToString());
        string joined = string.Join(' ', words);
        var elements = StringInfo.GetTextElementEnumerator(joined);
        var kept = new StringBuilder();
        for (int count = 0; count < MaximumNameCharacters && elements.MoveNext(); count++) kept.Append(elements.GetTextElement());
        return $"Crest Passwords - {(kept.Length == 0 ? fallbackName : kept.ToString())}.csv";
    }

    /// Whether `rune` is a letter, a mark or a number, as a name keeps it.
    private static bool IsAlphanumeric(Rune rune) => Rune.GetUnicodeCategory(rune) switch {
        UnicodeCategory.UppercaseLetter or UnicodeCategory.LowercaseLetter or UnicodeCategory.TitlecaseLetter
            or UnicodeCategory.ModifierLetter or UnicodeCategory.OtherLetter or UnicodeCategory.NonSpacingMark
            or UnicodeCategory.SpacingCombiningMark or UnicodeCategory.EnclosingMark or UnicodeCategory.DecimalDigitNumber
            or UnicodeCategory.LetterNumber or UnicodeCategory.OtherNumber => true,
        _ => false
    };

    /// Usernames as a person sorts them: ignoring case, with runs of digits
    /// compared as numbers.
    private static int CompareUsernames(string? left, string? right) =>
        string.Compare(left, right, CultureInfo.InvariantCulture, CompareOptions.IgnoreCase | CompareOptions.NumericOrdering);

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("CredentialExportFile { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(StringBuilder builder) {
        builder.Append($"FileName = {FileName}, Contents = <{Contents.Length} bytes redacted>");
        return true;
    }

    #endregion
}
