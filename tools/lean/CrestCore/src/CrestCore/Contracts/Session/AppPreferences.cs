namespace CrestCore.Contracts;

/// Device-local search and translation preferences.
public sealed record AppPreferences(string TranslationLanguage, SearchProvider SearchProvider,
    bool TranslateAutomatically, IReadOnlyList<string> ExcludedTranslationLanguages, bool SearchSuggestionsEnabled) {
    #region Static Variables

    public static AppPreferences Default { get; } = new(TranslationLanguage: "en", SearchProvider: SearchProvider.Google,
        TranslateAutomatically: false, ExcludedTranslationLanguages: [], SearchSuggestionsEnabled: false);

    #endregion
}
