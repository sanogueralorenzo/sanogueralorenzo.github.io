using CrestCore.Contracts;

namespace CrestCore.Domain;

#region Types

/// A row the palette ranked, with its score, the kind of result it is, the
/// page it leads to, and whether it may lead the palette as its best match.
internal sealed record PaletteCandidate(PaletteRow Row, PaletteSource Source, int Score, string? Place, bool MayLead);

#endregion

/// A window's command palette over the Space it shows: what it offers for
/// typed text and in what order. Each kind of result finds and scores its own
/// rows; the palette keeps one row per place, lets the first lead rule that
/// names a row lead, so Return runs it, follows with the address or search
/// for the text, names the search providers the text starts to name, which
/// the platform shows as chips Tab enters, then shows every kind under its
/// header in the person's order, or blended into one list, with suggestions
/// last. It reads only immutable records, so it answers without holding the
/// core's lock. Without a Space it may read, as a locked one, the palette
/// offers only the address or search, the commands and the other Spaces.
public sealed partial class Palette {
    #region Static Variables

    /// The longest text the palette asks suggestions for or offers as one.
    private const int MaximumSuggestionLength = 256;

    /// The most search providers the palette offers as chips for one word.
    private const int MaximumMatchingProviders = 8;

    #endregion

    #region Variables

    private readonly PaletteContext context;

    private PalettePreferences Preferences => context.Preferences;

    #endregion

    #region Constructors

    /// The palette of a window that shows `space`, or none the palette may
    /// read, and `shownTabId` there, in a private workspace or not, whose
    /// default engine opens internal pages or not, under the device's
    /// `app` preferences and its search `catalog`, with what the Space's
    /// `memory` holds, offering the workspace's other `spaces`, at `now`.
    public Palette(SpaceState? space, Guid? shownTabId, bool isPrivate, bool allowsInternalPages, AppPreferences app,
        SearchCatalog catalog, PaletteMemory memory, IReadOnlyList<SpaceState> spaces, DateTimeOffset now) {
        ArgumentNullException.ThrowIfNull(app);
        ArgumentNullException.ThrowIfNull(catalog);
        ArgumentNullException.ThrowIfNull(memory);
        ArgumentNullException.ThrowIfNull(spaces);
        context = new(space, shownTabId, isPrivate, allowsInternalPages, app.Palette, catalog, memory, spaces, now);
    }

    #endregion

    #region Actions - Answering

    /// What the palette offers for `question`: narrowed to a search provider
    /// or a scope when the person entered one or names one in the palette's
    /// notation, the resting rows before anything is typed, and otherwise
    /// every kind it ranks.
    public PaletteAnswer Answer(PaletteSuggestions question) {
        ArgumentNullException.ThrowIfNull(question);
        ArgumentNullException.ThrowIfNull(question.Text);
        var query = new PaletteQuery(question.Text);
        if (question.Provider is { } provider) return ProviderSearching(provider, query, question);
        if (question.Scope is { } scope) return Scoped(scope, query, question);
        if (PaletteNotation.Entry(context, question.Text) is { } entry) return Entered(entry, question);
        return query.IsEmpty ? Resting(question) : Typed(query, question);
    }

    /// What the palette offers once it enters what the text names in its
    /// notation, for the text that followed, with the entry the platform
    /// makes.
    private PaletteAnswer Entered(PaletteEntry entry, PaletteSuggestions question) =>
        Answer(question with { Text = entry.Text, Provider = entry.Provider, Scope = entry.Scope, Remote = [], Pasteboard = null })
            with { Entry = entry };

    /// The one search the provider the person entered runs for what was
    /// typed, then the suggestions fetched from the provider, each a search
    /// with it, where it offers them.
    private PaletteAnswer ProviderSearching(SearchProvider entered, PaletteQuery query, PaletteSuggestions question) {
        if (context.Catalog.Named(entered.Name) is not { } provider || query.IsEmpty) return Answered([]);
        var row = PaletteRow.Of(PaletteRowKind.Search, query.Text, provider.Kind.RowTitle(provider.Title), provider: provider,
            address: provider.Search(query.Text));
        List<PaletteGroup> groups = [new(PaletteSection.Intent, [row])];
        var suggestions = Suggestions(question.Text, question.Remote, [row], provider);
        if (suggestions.Count > 0) groups.Add(new(PaletteSection.SearchSuggestions, suggestions));
        return new(groups, null, ProviderSuggestionAddress(provider, query.Text), null, null, [], null);
    }

    /// Everything of the scope's kind that matches, or all of it before
    /// anything is typed, without a cap below the scope's own.
    private PaletteAnswer Scoped(PaletteScope scope, PaletteQuery query, PaletteSuggestions question) {
        var section = scope.Source.Section;
        var rows = scope.Source.Candidates(context, query, question, narrowed: true)
            .OrderByDescending(ranked => ranked.Score).Take(section.ScopedLimit).Select(ranked => ranked.Row).ToList();
        return Answered(rows.Count == 0 ? [] : [new(section, rows)]);
    }

    /// Before anything is typed: the rows offered above every section, then
    /// each kind's resting rows where the person ordered it, so the first of
    /// them holds the row Return runs.
    private PaletteAnswer Resting(PaletteSuggestions question) {
        List<PaletteGroup> groups = [];
        var offers = PaletteSource.All.Where(Preferences.Offers).SelectMany(source => source.RestingOffers(context, question)).ToList();
        if (offers.Count > 0) groups.Add(new(PaletteSection.Intent, offers));
        foreach (var source in Preferences.OrderedSections.Where(Preferences.Offers)) {
            var rows = source.RestingRows(context, question);
            if (rows.Count > 0 && source.RestingSection is { } section) groups.Add(new(section, rows));
        }
        return Answered(groups);
    }

    /// Typed text: the best match, the address or search, the offers Tab
    /// enters, and every kind ranked, with a completion and suggestions.
    private PaletteAnswer Typed(PaletteQuery query, PaletteSuggestions question) {
        var habit = Preferences.LearnsChoices ? context.Memory.Habit(query.Text, context.Now) : null;
        var completion = Completion(question);
        if (completion is not null && habit is not null && habit != PaletteDestination.Address(completion.Opens)) completion = null;
        var found = Intents(query);
        var ranked = Rank(query, question, found.FirstOrDefault());
        var lead = PaletteLeadRule.First(context,
            new(query, completion, question.AllowsCompletion ? habit : null, ranked, question.AllowsCompletion));
        if (lead is not null) ranked.RemoveAll(entry => entry.Row with { Reason = lead.Row.Reason } == lead.Row);
        List<PaletteGroup> groups = [];
        List<PaletteRow> intents = [];
        if (lead is not null && Preferences.ShowsTopHit) groups.Add(new(PaletteSection.TopHit, [lead.Row]));
        else if (lead is not null) intents.Add(lead.Row);
        intents.AddRange(found.Where(intent => intent.Address != lead?.Row.Address));
        var matching = MatchingProviders(query);
        var offered = matching.Count == 0
            ? null : new SearchOffer(matching[0], matching[0].HasShortcut(PaletteNotation.Provider.Word(query.Text)));
        foreach (var offer in PaletteSource.All.Where(Preferences.Offers).SelectMany(source => source.Offers(context, query, question)))
            if (offer.Address is null || offer.Address != lead?.Row.Address && intents.All(kept => kept.Address != offer.Address))
                intents.Add(offer);
        if (intents.Count > 0) groups.Add(new(PaletteSection.Intent, intents));
        var shown = groups.SelectMany(group => group.Rows).Concat(ranked.Select(entry => entry.Row)).ToList();
        groups.AddRange(Preferences.Layout.GroupsByKind ? Sections(ranked) : Blended(ranked));
        if (Preferences.Offers(PaletteSource.Suggestions)) {
            var suggestions = Suggestions(question.Text, question.Remote, shown, context.Search);
            if (suggestions.Count > 0) groups.Add(new(PaletteSection.SearchSuggestions, suggestions));
        }
        return new(groups, completion is null ? null : new(question.Text, completion.Text[question.Text.Length..], Accepted(completion)),
            SuggestionAddress(question.Text), offered, Preferences.Offers(PaletteSource.Scopes) ? PaletteScope.Keyed(query.Text) : null,
            matching, null);
    }

    private static PaletteAnswer Answered(IReadOnlyList<PaletteGroup> groups) => new(groups, null, null, null, null, [], null);

    #endregion

    #region Actions - Ranking

    /// Every row the offered kinds find for `query`, one per place: a page
    /// open in a tab is that tab, kept wins over history, and the address the
    /// text opens is never repeated as history. `intent` is the first row the
    /// text runs, whose address the text opens or searches.
    private List<PaletteCandidate> Rank(PaletteQuery query, PaletteSuggestions question, PaletteRow? intent) {
        List<PaletteCandidate> ranked = [.. PaletteSource.All.Where(Preferences.Offers)
            .SelectMany(source => source.Candidates(context, query, question, narrowed: false))];
        var claimed = new HashSet<string>(StringComparer.Ordinal);
        if (intent?.Address is { } opened && PaletteMemory.Place(opened) is { } intentPlace) claimed.Add(intentPlace);
        if (context.Space is { } space)
            foreach (var tab in space.Tabs)
                if ((tab.SavedAddress ?? tab.Url) is { } url && PaletteMemory.Place(url) is { } place) claimed.Add(place);
        ranked.RemoveAll(entry => entry.Source == PaletteSource.History && entry.Place is { } place && claimed.Contains(place));
        return ranked;
    }

    /// The search providers the text names or starts to name while it is one
    /// word, with or without the provider notation's sign, closest first and
    /// at most `MaximumMatchingProviders`; none once a space shows the text
    /// is not a provider's name.
    private IReadOnlyList<SearchProvider> MatchingProviders(PaletteQuery query) =>
        context.Space is not null && (Preferences.SearchesSitesWithTab || Preferences.ProviderSpaceTrigger.IsEnabled)
            && !query.Text.Any(char.IsWhiteSpace)
            ? [.. context.Catalog.Matching(PaletteNotation.Provider.Word(query.Text)).Take(MaximumMatchingProviders)] : [];

    #endregion

    #region Actions - Layout

    /// Each kind under its own header in the person's order, each capped.
    private IEnumerable<PaletteGroup> Sections(IReadOnlyList<PaletteCandidate> ranked) {
        foreach (var source in Preferences.OrderedSections.Where(Preferences.Offers)) {
            if (source == PaletteSource.Suggestions) continue;
            var rows = ranked.Where(entry => entry.Source.Section == source.Section)
                .OrderByDescending(entry => entry.Score).Take(Preferences.Limit(source)).Select(entry => entry.Row).ToList();
            if (rows.Count > 0) yield return new(source.Section, rows);
        }
    }

    /// Every kind in one list, best first, with no more of a kind than its
    /// own section would show.
    private IEnumerable<PaletteGroup> Blended(IReadOnlyList<PaletteCandidate> ranked) {
        var rows = ranked.GroupBy(entry => entry.Source)
            .SelectMany(kind => kind.OrderByDescending(entry => entry.Score).Take(Preferences.Limit(kind.Key)))
            .OrderByDescending(entry => entry.Score).Take(PaletteSection.Results.Limit)
            .Select(entry => entry.Row).ToList();
        if (rows.Count > 0) yield return new(PaletteSection.Results, rows);
    }

    #endregion
}
