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
