namespace CrestCore.Contracts;

#region Queries

/// The address typed input loads, or null when it names nothing a page can
/// load. `SearchQuery` is the text searched for when the address is a search.
public sealed record ResolvedAddress(string? Url, string? SearchQuery);

/// The results address of a selection search, or null when the selection is
/// blank or the address is one Crest does not open, and the title of the
/// engine that runs it.
public sealed record SelectionSearchAnswer(string? Url, string EngineTitle);

#endregion

#region Rejections

/// Another search provider a person added already uses this name, ignoring
/// case and diacritics.
public sealed record DuplicateSearchEngineName() : Rejection {
    #region Variables

    /// What the engine editor tells the person.
    [Localized]
    public string Message => "Another search provider already uses this name.";

    #endregion
}

/// A custom search engine has `Flaw`, the first rule it breaks.
public sealed record InvalidSearchEngine(SearchEngineFlaw Flaw) : Rejection;

/// The device already keeps `Limit` search providers a person added.
public sealed record SearchEngineLimitReached(int Limit) : Rejection {
    #region Variables

    /// What the provider editor tells the person.
    [Localized(Argument = nameof(Limit))]
    public string Message => "You can add up to %lld search providers.";

    #endregion
}

/// A shortcut is empty, has whitespace, a slash, a colon or a leading `@`,
/// or is longer than the limit.
public sealed record InvalidSearchShortcut() : Rejection {
    #region Variables

    /// What the provider editor tells the person.
    [Localized]
    public string Message => "Enter a shortcut without spaces, slashes or colons.";

    #endregion
}

/// Another search provider already answers to one of the shortcuts.
public sealed record DuplicateSearchShortcut() : Rejection {
    #region Variables

    /// What the provider editor tells the person.
    [Localized]
    public string Message => "Another search provider already uses this shortcut.";

    #endregion
}

/// `Option` is not one its provider offers, or refuses the value given.
public sealed record UnknownSearchOption(SearchProviderOption Option) : Rejection;

/// A website was offered as a default search, which only a search engine or
/// an AI assistant may be.
public sealed record UnsuitableDefaultSearch() : Rejection {
    #region Variables

    /// What Settings tells the person.
    [Localized]
    public string Message => "Choose a search engine or an AI assistant.";

    #endregion
}

#endregion

#region Changes

/// The device's search catalog, published whole whenever it changes, with
/// every provider it holds as the device searches with it, and the default
/// search a Space that follows it searches with, in an ordinary window and in
/// a private one.
public sealed record SearchCatalogChanged(SearchCatalog Catalog, IReadOnlyList<SearchProvider> Providers, SearchProvider Default,
    SearchProvider PrivateDefault) : Change {
    #region Constructors

    /// `catalog` as the platform reads it.
    internal static SearchCatalogChanged Of(SearchCatalog catalog) =>
        new(catalog, catalog.Providers, catalog.Default, catalog.PrivateDefault);

    #endregion
}

#endregion
