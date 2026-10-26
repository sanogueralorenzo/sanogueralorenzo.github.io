using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The fixed sources, ordering and limits used by every palette.
internal sealed class PaletteSource {
    #region Static Variables

    public static readonly PaletteSource RecentTabs = new(PaletteSection.RecentTabs, [new RecentTabFinder()], PaletteSection.RecentTabs);
    public static readonly PaletteSource OpenTabs = new(PaletteSection.Tabs, [new OpenTabFinder()]);
    public static readonly PaletteSource Saved = new(PaletteSection.Saved, [new SavedTabFinder(), new FolderFinder()]);
    public static readonly PaletteSource History = new(PaletteSection.History, [new HistoryFinder()]);
    public static readonly PaletteSource Actions = new(PaletteSection.Actions, [new CommandFinder()], PaletteSection.Actions);
    public static readonly PaletteSource Spaces = new(PaletteSection.Spaces, [new SpaceFinder()]);
    public static readonly PaletteSource Suggestions = new(PaletteSection.SearchSuggestions, []);
    public static readonly PaletteSource SettingsPages = new(PaletteSection.Actions, [new SettingsPageFinder()]);
    public static readonly PaletteSource Scopes = new(PaletteSection.Intent, [new ScopeFinder()]);
    public static readonly PaletteSource Calculator = new(PaletteSection.TopHit, []);

    public static IReadOnlyList<PaletteSource> Sections { get; } = [RecentTabs, OpenTabs, Saved, History, Actions, Spaces, Suggestions];
    public static IReadOnlyList<PaletteSource> All { get; } = [.. Sections, SettingsPages, Scopes, Calculator];

    #endregion

    #region Variables

    public PaletteSection Section { get; }
    public PaletteSection? RestingSection { get; }
    public int Limit => Section.Limit > 0 ? Section.Limit : Section.RestingLimit;
    private readonly IReadOnlyList<PaletteFinder> finders;

    #endregion

    #region Constructors

    private PaletteSource(PaletteSection section, IReadOnlyList<PaletteFinder> finders, PaletteSection? restingSection = null) {
        Section = section;
        RestingSection = restingSection;
        this.finders = finders;
    }

    #endregion

    #region Actions - Offering

    internal IEnumerable<PaletteCandidate> Candidates(PaletteContext context, PaletteQuery query, PaletteSuggestions question, bool narrowed) =>
        finders.SelectMany(finder => finder.Find(context, this, query, question, narrowed));

    internal IReadOnlyList<PaletteRow> RestingRows(PaletteContext context, PaletteSuggestions question) =>
        [.. finders.SelectMany(finder => finder.Resting(context, question))];

    internal IEnumerable<PaletteRow> Offers(PaletteContext context, PaletteQuery query, PaletteSuggestions question) =>
        finders.SelectMany(finder => finder.Offers(context, query, question));

    #endregion
}
