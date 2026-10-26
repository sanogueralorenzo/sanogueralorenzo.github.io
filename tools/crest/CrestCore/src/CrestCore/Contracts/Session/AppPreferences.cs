namespace CrestCore.Contracts;

/// Device-local search and translation preferences.
public sealed record AppPreferences(string TranslationLanguage, SearchProvider SearchProvider) {
    #region Static Variables

    public static AppPreferences Default { get; } = new(TranslationLanguage: "en", SearchProvider: SearchProvider.Google);

    #endregion
}
