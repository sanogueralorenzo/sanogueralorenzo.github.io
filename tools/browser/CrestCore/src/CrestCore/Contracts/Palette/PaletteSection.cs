namespace CrestCore.Contracts;

/// A group of the palette's rows. The best match and the address or search to
/// run have no header; each kind of thing the palette ranks shows under its
/// title, in the order the person's palette preferences set, and the blended
/// layout puts every ranked row in one headerless list. `Limit` caps the rows
/// the section shows; `RestingLimit` caps them before anything is typed;
/// `ScopedLimit` caps them when the person narrowed the palette to the kind.
/// A section travels as its index in `All`, so `All` is append-only.
public sealed class PaletteSection {
    #region Static Variables

    public static readonly PaletteSection Intent = new(name: "intent", title: null, limit: 2, restingLimit: 1, scopedLimit: 0);
    public static readonly PaletteSection SearchSuggestions = new(name: "searchSuggestions", title: "Search Suggestions", limit: 3,
        restingLimit: 0, scopedLimit: 0);
    public static readonly PaletteSection RecentTabs = new(name: "recentTabs", title: "Recent Tabs", limit: 0, restingLimit: 5,
        scopedLimit: 0);
    public static readonly PaletteSection Tabs = new(name: "tabs", title: "Tabs", limit: 8, restingLimit: 0, scopedLimit: 30);
    public static readonly PaletteSection Actions = new(name: "actions", title: "Actions", limit: 3, restingLimit: 3, scopedLimit: 30);
    public static readonly PaletteSection Saved = new(name: "saved", title: "Pinned & Saved", limit: 5, restingLimit: 0, scopedLimit: 30);
    public static readonly PaletteSection History = new(name: "history", title: "History", limit: 6, restingLimit: 0, scopedLimit: 30);
    public static readonly PaletteSection TopHit = new(name: "topHit", title: null, limit: 1, restingLimit: 0, scopedLimit: 0);
    public static readonly PaletteSection Spaces = new(name: "spaces", title: "Spaces", limit: 2, restingLimit: 0, scopedLimit: 30);
    public static readonly PaletteSection Archived = new(name: "archived", title: "Archived Tabs", limit: 3, restingLimit: 0,
        scopedLimit: 30);
    public static readonly PaletteSection Results = new(name: "results", title: null, limit: 12, restingLimit: 0, scopedLimit: 0);

    /// Every section, in the order sections were added.
    public static IReadOnlyList<PaletteSection> All { get; } =
        [Intent, SearchSuggestions, RecentTabs, Tabs, Actions, Saved, History, TopHit, Spaces, Archived, Results];

    #endregion

    #region Variables

    public string Name { get; }

    /// The header the palette shows above the section's rows, or null for none.
    [Localized]
    public string? Title { get; }

    /// The most rows the section shows for typed text.
    public int Limit { get; }

    /// The most rows the section shows before anything is typed.
    public int RestingLimit { get; }

    /// The most rows the section shows when the palette is narrowed to it.
    public int ScopedLimit { get; }

    #endregion

    #region Constructors

    private PaletteSection(string name, string? title, int limit, int restingLimit, int scopedLimit) {
        Name = name;
        Title = title;
        Limit = limit;
        RestingLimit = restingLimit;
        ScopedLimit = scopedLimit;
    }

    #endregion

    #region Actions - Lookup

    public static PaletteSection? Named(string? name) => All.FirstOrDefault(section => section.Name == name);

    /// How many rows the section shows: `RestingLimit` before anything is
    /// typed, `Limit` after.
    public int Shows(bool resting) => resting ? RestingLimit : Limit;

    #endregion
}
