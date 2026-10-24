using CrestCore.Domain;

namespace CrestCore.Contracts;

/// <summary>
/// The app-wide behavior preferences of one installation: what a window opens with,
/// page translation and its per-language rules, spelling, automatic Picture in
/// Picture, what closing a saved tab does, whether Split View focus follows the
/// pointer, whether local pages open with the developer toolbar, and how the
/// command palette ranks and arranges what it offers. Translation rules are in
/// ordinal order of their source language. They stay on this device and never
/// become sync records.
/// </summary>
public sealed record AppPreferences(StartupBehavior Startup, bool OffersTranslation, bool AutomaticallyTranslates,
    IReadOnlyList<TranslationRule> TranslationRules, bool ChecksSpelling, bool AutomaticallyEntersPictureInPicture,
    SavedTabClosePolicy SavedTabClose, bool SavedTabFaviconReturnsToSavedUrl, bool SplitFocusFollowsMouse,
    bool AutomaticallyShowsDeveloperToolbar, PalettePreferences Palette) {
    #region Static Variables

    /// The documented defaults for a person who never chose, which a platform
    /// shows and applies until its session holds the record.
    public static AppPreferences Default { get; } = new(StartupBehavior.ShowStartPage, OffersTranslation: true,
        AutomaticallyTranslates: false, TranslationRules: [], ChecksSpelling: false, AutomaticallyEntersPictureInPicture: true,
        SavedTabClosePolicy.ResumeLastLocation, SavedTabFaviconReturnsToSavedUrl: false, SplitFocusFollowsMouse: false,
        AutomaticallyShowsDeveloperToolbar: true, PalettePreferences.Default);

    #endregion

    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<TranslationRule> TranslationRules {
        get;
        init => field = [.. value];
    } = [.. TranslationRules];

    #endregion

    #region Actions - Translation

    /// Records a source language's translation choice through the rule set's
    /// alias rules.
    internal AppPreferences WithTranslationRule(string source, string target, bool isEnabled) =>
        this with { TranslationRules = AutomaticTranslationRules.Restore(TranslationRules).Set(source, target, isEnabled).Rules };

    #endregion

    #region Actions - Equality

    public bool Equals(AppPreferences? other) => other is not null
        && Startup == other.Startup
        && OffersTranslation == other.OffersTranslation
        && AutomaticallyTranslates == other.AutomaticallyTranslates
        && TranslationRules.SequenceEqual(other.TranslationRules)
        && ChecksSpelling == other.ChecksSpelling
        && AutomaticallyEntersPictureInPicture == other.AutomaticallyEntersPictureInPicture
        && SavedTabClose == other.SavedTabClose
        && SavedTabFaviconReturnsToSavedUrl == other.SavedTabFaviconReturnsToSavedUrl
        && SplitFocusFollowsMouse == other.SplitFocusFollowsMouse
        && AutomaticallyShowsDeveloperToolbar == other.AutomaticallyShowsDeveloperToolbar
        && Palette.Equals(other.Palette);

    public override int GetHashCode() => HashCode.Combine(Startup, OffersTranslation, AutomaticallyTranslates,
        TranslationRules.Count, ChecksSpelling, AutomaticallyEntersPictureInPicture, SavedTabClose,
        HashCode.Combine(SavedTabFaviconReturnsToSavedUrl, SplitFocusFollowsMouse, AutomaticallyShowsDeveloperToolbar, Palette));

    #endregion
}
