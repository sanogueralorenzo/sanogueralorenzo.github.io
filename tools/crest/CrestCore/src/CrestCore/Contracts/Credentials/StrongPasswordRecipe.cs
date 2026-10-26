namespace CrestCore.Contracts;

/// How a strong password is composed: its length and the character groups it
/// draws from. The platform draws one character from every group, fills the
/// rest from all groups and shuffles, using its own secure random source, so
/// the password itself never exists in the core. Crest's four explicit groups
/// meet common website requirements; characters that are easily confused in
/// proportional fonts are absent.
public sealed record StrongPasswordRecipe(int Length, IReadOnlyList<string> Groups) {
    #region Static Variables

    internal const int DefaultLength = 20;
    internal const int MinimumLength = 16;
    internal const int MaximumLength = 64;

    private static readonly string[] CharacterGroups = [
        "abcdefghijkmnopqrstuvwxyz",
        "ABCDEFGHJKLMNPQRSTUVWXYZ",
        "23456789",
        "-_.!@#$%^&*+="
    ];

    #endregion

    #region Actions - Generation

    /// The recipe for a password of `length` characters, or the default length.
    internal static StrongPasswordRecipe For(int? length) {
        int resolved = length ?? DefaultLength;
        if (resolved is < MinimumLength or > MaximumLength) throw new Rejected(new InvalidPasswordLength(MinimumLength, MaximumLength));
        return new(resolved, CharacterGroups);
    }

    #endregion
}
