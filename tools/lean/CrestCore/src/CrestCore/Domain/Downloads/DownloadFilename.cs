using System.Globalization;
using System.Text;

namespace CrestCore.Domain;

/// The name a download's record shows for the file an engine names: its last
/// path component, in composed form, without control or direction-changing
/// characters that could disguise its type, without path separators, trimmed of
/// edge spaces and dots, and no longer than a file system allows. The platform's
/// `BrowserDownloadDestination.safeFilename` names files the same way.
public static class DownloadFilename {
    #region Variables

    /// The longest name, in UTF-8 bytes, left room for a numbered duplicate.
    public const int MaximumByteCount = 240;

    /// The name a download takes when nothing of its own name is left.
    public const string Fallback = "download";

    /// The longest extension a shortened name keeps, in UTF-8 bytes.
    private const int MaximumExtensionByteCount = 32;

    #endregion

    #region Actions - Naming

    public static string Safe(string suggested) {
        ArgumentNullException.ThrowIfNull(suggested);
        string last = suggested.Replace('\\', '/').Split('/', StringSplitOptions.RemoveEmptyEntries).LastOrDefault() ?? "";
        var kept = new StringBuilder();
        foreach (var rune in last.Normalize(NormalizationForm.FormC).EnumerateRunes()) {
            if (IsDeceptiveOrControl(rune.Value)) continue;
            kept.Append(rune.Value is '/' or '\\' or ':' ? "_" : rune.ToString());
        }
        string cleaned = Trimmed(kept.ToString());
        return cleaned.Length == 0 ? Fallback : Shortened(cleaned);
    }

    #endregion

    #region Actions - Rules

    private static bool IsDeceptiveOrControl(int value) => value < 0x20
        || value is >= 0x7F and <= 0x9F
        || value == 0x061C
        || value is >= 0x200B and <= 0x200F
        || value is >= 0x202A and <= 0x202E
        || value is >= 0x2066 and <= 0x2069
        || value == 0xFEFF;

    /// Leading and trailing spaces, line breaks and dots removed.
    private static string Trimmed(string name) {
        int start = 0;
        int end = name.Length;
        while (start < end && (char.IsWhiteSpace(name[start]) || name[start] == '.')) start++;
        while (end > start && (char.IsWhiteSpace(name[end - 1]) || name[end - 1] == '.')) end--;
        return name[start..end];
    }

    /// A name over the limit keeps its extension when that is short, and as
    /// many whole characters of its stem as fit.
    private static string Shortened(string name) {
        if (Encoding.UTF8.GetByteCount(name) <= MaximumByteCount) return name;
        int dot = name.LastIndexOf('.');
        string extension = dot > 0 ? name[dot..] : "";
        if (Encoding.UTF8.GetByteCount(extension) > MaximumExtensionByteCount) extension = "";
        string stem = extension.Length == 0 ? name : name[..dot];
        int available = MaximumByteCount - Encoding.UTF8.GetByteCount(extension);
        var result = new StringBuilder();
        var characters = StringInfo.GetTextElementEnumerator(stem);
        while (characters.MoveNext()) {
            string character = characters.GetTextElement();
            if (Encoding.UTF8.GetByteCount(result.ToString() + character) > available) break;
            result.Append(character);
        }
        string trimmed = result.ToString().Trim();
        return (trimmed.Length == 0 ? Fallback : trimmed) + extension;
    }

    #endregion
}
