using CrestCore.Contracts;

namespace CrestCore.Domain;

/// Reads an @ scope followed by a space and the text to search within it.
internal static class PaletteNotation {
    #region Actions - Reading

    public static PaletteEntry? Entry(PaletteContext context, string typed) {
        ArgumentNullException.ThrowIfNull(context);
        ArgumentNullException.ThrowIfNull(typed);
        string text = typed.TrimStart();
        int space = text.IndexOfAny([' ', '\t', ' ']);
        return space >= 2 && text[0] == '@' && PaletteScope.Keyed(text[..space]) is { } scope
            ? new(scope, text[(space + 1)..].TrimStart()) : null;
    }

    #endregion
}
