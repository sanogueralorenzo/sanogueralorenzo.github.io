using CrestCore.Domain;

namespace CrestCore.Contracts;

#region Types

/// One kind of result, whether the palette offers it, and the most rows it
/// shows, or null for the kind's own number. In `PalettePreferences.Sources`
/// the order of the kinds that are sections is the order the palette shows
/// them.
public sealed record PaletteSourceChoice(PaletteSource Source, bool IsEnabled, int? Limit);

#endregion

/// How the command palette ranks and arranges what it offers, which this
/// device keeps among its app-wide preferences and never syncs: whether rows
/// stay under a header for their kind or blend into one ranked list, which
/// kinds it offers, in what order and how many rows each shows, whether one
/// best row leads, whether an open tab outranks history for the same site,
/// whether it completes addresses inline, learns from the rows a person picks,
/// searches a site when Tab follows its shortcut, and says why a row is there.
public sealed record PalettePreferences(PaletteLayout Layout, IReadOnlyList<PaletteSourceChoice> Sources, bool ShowsTopHit,
    bool PrefersOpenTabs, bool CompletesInline, bool LearnsChoices, bool SearchesSitesWithTab, bool ShowsReasons) {
    #region Static Variables

    /// The most rows a person may have one kind show.
    public const int MaximumLimit = 50;

    /// What a person who never chose sees: every kind in its default order,
    /// each on or off as `PaletteSource.IsEnabledByDefault` says.
    public static PalettePreferences Default { get; } = new(PaletteLayout.Sections,
        [.. PaletteSource.All.Select(source => new PaletteSourceChoice(source, source.IsEnabledByDefault, Limit: null))], ShowsTopHit: true, PrefersOpenTabs: true, CompletesInline: true, LearnsChoices: true, SearchesSitesWithTab: true,
        ShowsReasons: false);

    #endregion

    #region Variables

    /// Collections are owned when constructed or replaced on a copy.
    public IReadOnlyList<PaletteSourceChoice> Sources {
        get;
        init => field = [.. value];
    } = [.. Sources];

    #endregion

    #region Actions - Reading

    /// Whether the palette offers results of `source`.
    public bool Offers(PaletteSource source) => Sources.FirstOrDefault(choice => choice.Source == source)?.IsEnabled ?? false;

    /// The kinds the palette shows as sections, in the person's order, on or off.
    public IEnumerable<PaletteSource> OrderedSections => Sources.Select(choice => choice.Source).Where(source => source.IsSection);

    /// The most rows `source` shows: the person's number, else the kind's own.
    public int Limit(PaletteSource source) =>
        Sources.FirstOrDefault(choice => choice.Source == source)?.Limit ?? source.DefaultLimit;

    #endregion

    #region Actions - Restoring

    /// These preferences with every kind named exactly once: a kind repeated
    /// keeps its first place, a number of rows outside one to `MaximumLimit`
    /// goes back to the kind's own, and a kind they never named, such as one a
    /// later release added, joins after the others with its default.
    public PalettePreferences Restored() {
        List<PaletteSourceChoice> restored = [];
        foreach (var choice in Sources)
            if (restored.All(kept => kept.Source != choice.Source))
                restored.Add(choice.Limit is > 0 and <= MaximumLimit ? choice : choice with { Limit = null });
        foreach (var source in PaletteSource.All)
            if (restored.All(kept => kept.Source != source)) restored.Add(new(source, source.IsEnabledByDefault, Limit: null));
        return this with { Sources = restored };
    }

    #endregion

    #region Actions - Equality

    public bool Equals(PalettePreferences? other) => other is not null
        && Layout == other.Layout
        && Sources.SequenceEqual(other.Sources)
        && ShowsTopHit == other.ShowsTopHit
        && PrefersOpenTabs == other.PrefersOpenTabs
        && CompletesInline == other.CompletesInline
        && LearnsChoices == other.LearnsChoices
        && SearchesSitesWithTab == other.SearchesSitesWithTab
        && ShowsReasons == other.ShowsReasons;

    public override int GetHashCode() =>
        HashCode.Combine(Layout, Sources.Count, ShowsTopHit, PrefersOpenTabs, CompletesInline, LearnsChoices, SearchesSitesWithTab, ShowsReasons);

    #endregion
}

/// How the palette arranges its rows: under a header for each kind of
/// result, or as one list ranked across kinds, where each row names its kind.
/// The stored preferences spell a layout as its `Name`, so a name never
/// changes. A layout travels as its index in `All`, so `All` is append-only.
public sealed class PaletteLayout {
    #region Static Variables

    public static readonly PaletteLayout Sections = new(name: "sections", title: "Sections", groupsByKind: true);
    public static readonly PaletteLayout Blended = new(name: "blended", title: "Blended", groupsByKind: false);

    /// The layouts, in the order the settings offer them.
    public static IReadOnlyList<PaletteLayout> All { get; } = [Sections, Blended];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the settings call the layout.
    [Localized]
    public string Title { get; }

    /// Rows stay under the header of their kind.
    public bool GroupsByKind { get; }

    #endregion

    #region Constructors

    private PaletteLayout(string name, string title, bool groupsByKind) {
        Name = name;
        Title = title;
        GroupsByKind = groupsByKind;
    }

    #endregion

    #region Actions - Lookup

    public static PaletteLayout? Named(string? name) => All.FirstOrDefault(layout => layout.Name == name);

    #endregion
}

/// A kind of result the palette may offer, which a person turns on or off,
/// and which finds and scores its own rows through its finders, one for each
/// kind of row it offers. A kind that is a section shows its rows under its
/// own header, in the order the person set; the others join `Section` or,
/// with none, lead the list. Before anything is typed only the kinds with a `RestingSection`
/// show, in that same order, so the first of them holds the row Return runs.
/// The stored preferences spell a kind as its `Name`, so a name never
/// changes. A kind travels as its index in `All`, so `All` is append-only.
public sealed class PaletteSource {
    #region Static Variables

    public static readonly PaletteSource RecentTabs = new(name: "recentTabs", title: "Recent Tabs", detail: null, section: PaletteSection.RecentTabs,
        isSection: true, isEnabledByDefault: true, restingSection: PaletteSection.RecentTabs, finders: [new RecentTabFinder()]);
    public static readonly PaletteSource OpenTabs = new(name: "openTabs", title: "Open Tabs", detail: null, section: PaletteSection.Tabs,
        isSection: true, isEnabledByDefault: true, restingSection: null, finders: [new OpenTabFinder()]);
    public static readonly PaletteSource Saved = new(name: "saved", title: "Pinned & Saved", detail: null, section: PaletteSection.Saved,
        isSection: true, isEnabledByDefault: true, restingSection: null, finders: [new SavedTabFinder(), new FolderFinder()]);
    public static readonly PaletteSource History = new(name: "history", title: "History", detail: null, section: PaletteSection.History,
        isSection: true, isEnabledByDefault: true, restingSection: null, finders: [new HistoryFinder()]);
    public static readonly PaletteSource Actions = new(name: "actions", title: "Actions", detail: null, section: PaletteSection.Actions,
        isSection: true, isEnabledByDefault: true, restingSection: PaletteSection.Actions, finders: [new CommandFinder()]);
    public static readonly PaletteSource Spaces = new(name: "spaces", title: "Spaces", detail: null, section: PaletteSection.Spaces,
        isSection: true, isEnabledByDefault: true, restingSection: null, finders: [new SpaceFinder()]);
    public static readonly PaletteSource ArchivedTabs = new(name: "archivedTabs", title: "Archived Tabs", detail: null,
        section: PaletteSection.Archived, isSection: true, isEnabledByDefault: false, restingSection: null, finders: [new ArchiveFinder()]);
    public static readonly PaletteSource Suggestions = new(name: "suggestions", title: "Search Suggestions", detail: null,
        section: PaletteSection.SearchSuggestions, isSection: true, isEnabledByDefault: true, restingSection: null, finders: []);
    public static readonly PaletteSource SettingsPages = new(name: "settingsPages", title: "Settings Pages", detail: "Finds Settings pages by name.",
        section: PaletteSection.Actions, isSection: false, isEnabledByDefault: true, restingSection: null, finders: [new SettingsPageFinder()]);
    public static readonly PaletteSource Scopes = new(name: "scopes", title: "@ Filters", detail: "Type @tabs, @saved, @history, @actions or @spaces, then a space or Tab, to show only that kind.", section: PaletteSection.Intent,
        isSection: false, isEnabledByDefault: true, restingSection: null, finders: [new ScopeFinder()]);
    public static readonly PaletteSource Calculator = new(name: "calculator", title: "Calculator", detail: "Answers arithmetic such as 24 * 7. Return copies the answer.", section: PaletteSection.TopHit,
        isSection: false, isEnabledByDefault: true, restingSection: null, finders: []);
    public static readonly PaletteSource PasteAndGo = new(name: "pasteAndGo", title: "Paste and Go", detail: "Offers the address you copied when the palette opens.", section: PaletteSection.Intent,
        isSection: false, isEnabledByDefault: false, restingSection: null, finders: [new PasteFinder()]);

    /// The kinds, sections first in their default order.
    public static IReadOnlyList<PaletteSource> All { get; } =
        [RecentTabs, OpenTabs, Saved, History, Actions, Spaces, ArchivedTabs, Suggestions, SettingsPages, Scopes, Calculator, PasteAndGo];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the settings call the kind.
    [Localized]
    public string Title { get; }

    /// What the settings say the kind does, where its title alone does not.
    [Localized]
    public string? Detail { get; }

    /// Where the kind's rows go when the palette shows sections.
    public PaletteSection Section { get; }

    /// The kind shows its rows under its own header, in the order the person set.
    public bool IsSection { get; }

    /// Whether the palette offers the kind for a person who never chose.
    public bool IsEnabledByDefault { get; }

    /// Where the kind's rows go before anything is typed, or null when it
    /// offers none then.
    public PaletteSection? RestingSection { get; }

    /// The most rows the kind shows unless the person chose a number: its
    /// section's, or before anything is typed for a kind that only shows then.
    public int DefaultLimit => Section.Limit > 0 ? Section.Limit : Section.RestingLimit;

    /// How the kind finds and scores its rows, each finder a kind of row it offers.
    private readonly IReadOnlyList<PaletteFinder> finders;

    #endregion

    #region Constructors

    private PaletteSource(string name, string title, string? detail, PaletteSection section, bool isSection, bool isEnabledByDefault,
        PaletteSection? restingSection, IReadOnlyList<PaletteFinder> finders) {
        Name = name;
        Title = title;
        Detail = detail;
        Section = section;
        IsSection = isSection;
        IsEnabledByDefault = isEnabledByDefault;
        RestingSection = restingSection;
        this.finders = finders;
    }

    #endregion

    #region Actions - Lookup

    public static PaletteSource? Named(string? name) => All.FirstOrDefault(source => source.Name == name);

    #endregion

    #region Actions - Offering

    /// The rows the kind offers for `query`, every one when the person
    /// narrowed the palette to it and typed nothing.
    internal IEnumerable<PaletteCandidate> Candidates(PaletteContext context, PaletteQuery query, PaletteSuggestions question, bool narrowed) =>
        finders.SelectMany(finder => finder.Find(context, this, query, question, narrowed));

    /// The rows the kind offers before anything is typed.
    internal IReadOnlyList<PaletteRow> RestingRows(PaletteContext context, PaletteSuggestions question) =>
        [.. finders.SelectMany(finder => finder.Resting(context, question))];

    /// The rows the kind adds beside the address or search typed text runs.
    internal IEnumerable<PaletteRow> Offers(PaletteContext context, PaletteQuery query, PaletteSuggestions question) =>
        finders.SelectMany(finder => finder.Offers(context, query, question));

    /// The rows the kind adds before anything is typed, above every section.
    internal IEnumerable<PaletteRow> RestingOffers(PaletteContext context, PaletteSuggestions question) =>
        finders.SelectMany(finder => finder.RestingOffers(context, question));

    #endregion
}
