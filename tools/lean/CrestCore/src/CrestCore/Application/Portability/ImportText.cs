using System.Globalization;

namespace CrestCore.Application;

/// Text an import keeps: a title, name or symbol, with its length counted in
/// characters as a person sees them.
internal static class ImportText {
    #region Static Variables

    public const int MaximumSpaceName = 200;
    public const int MaximumFolderTitle = 500;
    public const int MaximumTitle = 4_096;
    public const int MaximumSymbol = 128;

    #endregion

    #region Actions - Text

    /// `source` with every run of white space made one space and none at
    /// either end.
    public static string Collapsed(string source) =>
        string.Join(' ', source.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));

    /// `source` collapsed, or `fallback` collapsed when nothing is left.
    public static string Title(string? source, string fallback) {
        string collapsed = Collapsed(source ?? "");
        return collapsed.Length == 0 ? Collapsed(fallback) : collapsed;
    }

    /// The title `source` gives, falling back to `fallback`, or null when it
    /// is empty or longer than `maximum` characters.
    public static string? Bounded(string? source, string fallback, int maximum) {
        string title = Title(source, fallback);
        return title.Length == 0 || Length(title) > maximum ? null : title;
    }

    /// Whether `value` holds something besides white space and is at most
    /// `maximum` characters.
    public static bool IsKept(string value, int maximum) => value.Trim().Length > 0 && Length(value) <= maximum;

    /// The characters a person sees in `value`.
    public static int Length(string value) => new StringInfo(value).LengthInTextElements;

    #endregion
}
