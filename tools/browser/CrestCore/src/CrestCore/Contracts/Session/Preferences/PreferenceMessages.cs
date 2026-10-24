namespace CrestCore.Contracts;

#region Intents

/// The behavior preferences as an older release's settings stored them, each
/// null when it was never saved. Terms are the stored spellings, which the core
/// reads tolerantly, and `TranslationRules` is the rule set as the settings
/// stored it, a JSON document.
public sealed record LegacyAppPreferences(
    string? StartupBehavior,
    bool? OffersTranslation,
    bool? AutomaticallyTranslates,
    string? TranslationRules,
    bool? ChecksSpelling,
    bool? AutomaticallyEntersPictureInPicture,
    string? SavedTabClosePolicy,
    bool? SavedTabFaviconReturnsToSavedUrl,
    bool? SplitFocusFollowsMouse);

#endregion

#region Queries

/// For each candidate, in order, whether it names the asked language.
public sealed record LanguageMatches(IReadOnlyList<bool> Matches);

/// How one launch treats the person's data and what its first window opens.
/// An isolated launch never reads or writes the installed profile.
/// `UsesEphemeralProfileStorage` keeps page and extension web storage in the
/// same privacy class: both forget, unless a named isolated profile persists
/// both. `PresentsInstalledApplicationUI` is false only under the test runtime.
public sealed record LaunchDecision(bool RequiresIsolation, bool UsesEphemeralProfileStorage, bool PresentsInstalledApplicationUI,
    StartupBehavior Startup);

/// The rule that applies to a source language, or null, and the language its
/// pages are translated into, or null when they are not.
public sealed record TranslationDecision(TranslationRule? Rule, string? Target);

#endregion

#region Rejections

/// A language identifier is longer than `Limit` characters.
public sealed record LanguageTooLong(int Limit) : Rejection;

/// Only the persistent workspace keeps the app-wide preferences and takes
/// imported Spaces.
public sealed record PersistentWorkspaceRequired(Guid WorkspaceId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Open a regular window to do this.";

    #endregion
}

/// Translation rules already cover `Limit` source languages.
public sealed record TranslationRuleLimitReached(int Limit) : Rejection;

#endregion
