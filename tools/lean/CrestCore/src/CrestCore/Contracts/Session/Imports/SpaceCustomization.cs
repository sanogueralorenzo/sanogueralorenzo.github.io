using CrestCore.Domain;

namespace CrestCore.Contracts;

/// The name an imported or drafted Space takes. A blank name reads as `UntitledName`.
public sealed record SpaceCustomization(string Name) {
    #region Static Variables

    /// What a Space named with nothing but blanks is called.
    public const string UntitledName = "Untitled Space";

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

    #endregion
}
