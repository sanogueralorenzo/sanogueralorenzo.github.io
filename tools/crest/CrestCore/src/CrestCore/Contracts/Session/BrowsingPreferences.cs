namespace CrestCore.Contracts;

/// <summary>
/// How a Space searches and how long it keeps what it browses. While
/// <see cref="FollowsDefaultSearch"/> the Space searches with the device's
/// default search; otherwise with a built-in provider or one a person added,
/// and exactly one of <see cref="SelectedBuiltInEngine"/> and
/// <see cref="SelectedCustomEngineId"/> names it. A Space that searches with a
/// provider a person added carries its definition in
/// <see cref="CustomSearchProviders"/>. While
/// <see cref="FollowsDefaultSuggestions"/> it suggests searches as the device's
/// default does; otherwise as <see cref="SearchSuggestionsEnabled"/> says.
/// Older releases read only the selection and the suggestions, which a Space
/// that follows the default keeps as the default was when it last chose.
/// </summary>
public sealed record BrowsingPreferences(
    BuiltInSearchProvider? SelectedBuiltInEngine,
    Guid? SelectedCustomEngineId,
    IReadOnlyList<CustomSearchProvider> CustomSearchProviders,
    bool SearchSuggestionsEnabled,
    bool FollowsDefaultSearch,
    bool FollowsDefaultSuggestions,
    CurrentTabCleanup CurrentTabCleanup,
    ContentBlockingPolicy ContentBlocking,
    DataRetentionPreferences DataRetention) {
    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<CustomSearchProvider> CustomSearchProviders {
        get;
        init => field = [.. value];
    } = [.. CustomSearchProviders];

    #endregion

    #region Actions - Equality

    public bool Equals(BrowsingPreferences? other) => other is not null
        && SelectedBuiltInEngine == other.SelectedBuiltInEngine
        && SelectedCustomEngineId == other.SelectedCustomEngineId
        && CustomSearchProviders.SequenceEqual(other.CustomSearchProviders)
        && SearchSuggestionsEnabled == other.SearchSuggestionsEnabled
        && FollowsDefaultSearch == other.FollowsDefaultSearch
        && FollowsDefaultSuggestions == other.FollowsDefaultSuggestions
        && CurrentTabCleanup == other.CurrentTabCleanup
        && ContentBlocking == other.ContentBlocking
        && DataRetention == other.DataRetention;

    public override int GetHashCode() => HashCode.Combine(SelectedBuiltInEngine, SelectedCustomEngineId, CustomSearchProviders.Count,
        SearchSuggestionsEnabled, HashCode.Combine(FollowsDefaultSearch, FollowsDefaultSuggestions), CurrentTabCleanup, ContentBlocking,
        DataRetention);

    #endregion
}
