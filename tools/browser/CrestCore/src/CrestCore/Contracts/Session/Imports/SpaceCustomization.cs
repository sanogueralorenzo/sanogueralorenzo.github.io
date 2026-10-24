using CrestCore.Domain;

namespace CrestCore.Contracts;

/// The name, symbol, accent and look an imported or drafted Space takes. A
/// blank name reads as `UntitledName` and a blank symbol as the default one;
/// the look is kept within the ranges every device draws.
public sealed record SpaceCustomization(string Name, string Symbol, SpaceAccent Accent, SpaceBranding Branding) {
    #region Static Variables

    /// What a Space named with nothing but blanks is called.
    public const string UntitledName = "Untitled Space";

    /// The symbol a Space given a blank one wears.
    private const string DefaultSymbol = "square.grid.2x2";

    #endregion

    #region Actions - Names

    /// The name `name` gives a Space: trimmed, or `UntitledName` when blank.
    public static string Resolved(string name) => string.IsNullOrWhiteSpace(name) ? UntitledName : name.Trim();

    /// The name a person gave a Space, trimmed, as `Resolved` reads it. Throws
    /// `Rejected` with `InvalidName` for one longer than a Space name holds.
    internal static string Chosen(string name) {
        var resolved = Resolved(name);
        if (resolved.Length > BrowserTabCollection.MaximumNameLength)
            throw new Rejected(new InvalidName(BrowserTabCollection.MaximumNameLength));
        return resolved;
    }

    /// The symbol `symbol` gives a Space: trimmed, or the default one when blank.
    internal static string ResolvedSymbol(string symbol) => string.IsNullOrWhiteSpace(symbol) ? DefaultSymbol : symbol.Trim();

    #endregion
}
