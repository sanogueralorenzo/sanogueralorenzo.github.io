using CrestCore.Contracts;

namespace CrestCore.Domain;

#region Types

/// A row the palette ranked, with its score, the kind of result it is, the
/// page it leads to, and whether it may lead the palette as its best match.
internal sealed record PaletteCandidate(PaletteRow Row, PaletteSource Source, int Score, string? Place, bool MayLead);

#endregion

public sealed partial class Palette {
    #region Static Variables

    /// The longest text the palette asks suggestions for or offers as one.
    private const int MaximumSuggestionLength = 256;

    #endregion

    #region Variables

    private readonly PaletteContext context;

    #endregion

    #region Constructors

    /// The palette of a window that shows `space`, or none the palette may
    /// read, and `shownTabId` there, in a private workspace or not, whose
    /// engine opens internal pages or not, offering the workspace's other
    /// `spaces` and ranking its history at `now`.
    public Palette(SpaceState? space, Guid? shownTabId, bool isPrivate, bool allowsInternalPages,
        IReadOnlyList<SpaceState> spaces, DateTimeOffset now, SearchProvider provider, bool suggests) {
        ArgumentNullException.ThrowIfNull(spaces);
        context = new(space, shownTabId, isPrivate, allowsInternalPages, spaces, now, provider, suggests);
    }

    #endregion

    #region Actions - Answering

    /// What the palette offers for `question`: narrowed to a local scope
    /// when the person entered one or names one in the palette's
    /// notation, the resting rows before anything is typed, and otherwise
    /// every kind it ranks.
    public PaletteAnswer Answer(PaletteSuggestions question) {
        ArgumentNullException.ThrowIfNull(question);
        ArgumentNullException.ThrowIfNull(question.Text);
        var query = new PaletteQuery(question.Text);
        if (question.Scope is { } scope) return Scoped(scope, query, question);
        if (PaletteNotation.Entry(context, question.Text) is { } entry) return Entered(entry, question);
        return query.IsEmpty ? Resting(question) : Typed(query, question);
    }

    /// What the palette offers once it enters what the text names in its
    /// notation, for the text that followed, with the entry the platform
    /// makes.
    private PaletteAnswer Entered(PaletteEntry entry, PaletteSuggestions question) =>
        Answer(question with { Text = entry.Text, Scope = entry.Scope, Remote = [] })
            with { Entry = entry };

    /// Everything of the scope's kind that matches, or all of it before
    /// anything is typed, without a cap below the scope's own.
    private PaletteAnswer Scoped(PaletteScope scope, PaletteQuery query, PaletteSuggestions question) {
        var section = scope.Source.Section;
        var rows = scope.Source.Candidates(context, query, question, narrowed: true)
            .OrderByDescending(ranked => ranked.Score).Take(section.ScopedLimit).Select(ranked => ranked.Row).ToList();
        return Answered(rows.Count == 0 ? [] : [new(section, rows)]);
    }

    /// Before anything is typed: the rows offered above every section, then
    /// each kind's resting rows in the fixed source order, so the first of
    /// them holds the row Return runs.
    private PaletteAnswer Resting(PaletteSuggestions question) {
        List<PaletteGroup> groups = [];
        foreach (var source in PaletteSource.Sections) {
            var rows = source.RestingRows(context, question);
            if (rows.Count > 0 && source.RestingSection is { } section) groups.Add(new(section, rows));
        }
        return Answered(groups);
    }

    /// Typed text: the best match, the address or search, the offers Tab
    /// enters, and every kind ranked, with a completion and suggestions.
    private PaletteAnswer Typed(PaletteQuery query, PaletteSuggestions question) {
        var completion = Completion(question);
        var found = Intents(query);
        var ranked = Rank(query, question, found.FirstOrDefault());
        var lead = PaletteLeadRule.First(context,
            new(query, completion, ranked, question.AllowsCompletion));
        if (lead is not null) ranked.RemoveAll(entry => entry.Row with { Reason = lead.Row.Reason } == lead.Row);
        List<PaletteGroup> groups = [];
        List<PaletteRow> intents = [];
        if (lead is not null) groups.Add(new(PaletteSection.TopHit, [lead.Row]));
        intents.AddRange(found.Where(intent => intent.Address != lead?.Row.Address));
        foreach (var offer in PaletteSource.All.SelectMany(source => source.Offers(context, query, question)))
            if (offer.Address is null || offer.Address != lead?.Row.Address && intents.All(kept => kept.Address != offer.Address))
                intents.Add(offer);
        if (intents.Count > 0) groups.Add(new(PaletteSection.Intent, intents));
        var shown = groups.SelectMany(group => group.Rows).Concat(ranked.Select(entry => entry.Row)).ToList();
        groups.AddRange(Sections(ranked));
        var suggestions = Suggestions(question.Text, question.Remote, shown, context.Provider);
        if (suggestions.Count > 0) groups.Add(new(PaletteSection.SearchSuggestions, suggestions));
        return new(groups, completion is null ? null : new(question.Text, completion.Text[question.Text.Length..], Accepted(completion)),
            SuggestionAddress(question.Text), PaletteScope.Keyed(query.Text), null);
    }

    private static PaletteAnswer Answered(IReadOnlyList<PaletteGroup> groups) => new(groups, null, null, null, null);

    #endregion

    #region Actions - Ranking

    /// Every row the offered kinds find for `query`, one per place: a page
    /// open in a tab is that tab, kept wins over history, and the address the
    /// text opens is never repeated as history. `intent` is the first row the
    /// text runs, whose address the text opens or searches.
    private List<PaletteCandidate> Rank(PaletteQuery query, PaletteSuggestions question, PaletteRow? intent) {
        List<PaletteCandidate> ranked = [.. PaletteSource.All
            .SelectMany(source => source.Candidates(context, query, question, narrowed: false))];
        var claimed = new HashSet<string>(StringComparer.Ordinal);
        if (intent?.Address is { } opened && new WebAddress(opened).Place is { } intentPlace) claimed.Add(intentPlace);
        if (context.Space is { } space)
            foreach (var tab in space.Tabs)
                if ((tab.SavedAddress ?? tab.Url) is { } url && new WebAddress(url).Place is { } place) claimed.Add(place);
        ranked.RemoveAll(entry => entry.Source == PaletteSource.History && entry.Place is { } place && claimed.Contains(place));
        return ranked;
    }

    #endregion

    #region Actions - Layout

    /// Each kind under its own header in the fixed source order, each capped.
    private IEnumerable<PaletteGroup> Sections(IReadOnlyList<PaletteCandidate> ranked) {
        foreach (var source in PaletteSource.Sections) {
            if (source == PaletteSource.Suggestions) continue;
            var rows = ranked.Where(entry => entry.Source.Section == source.Section)
                .OrderByDescending(entry => entry.Score).Take(source.Limit).Select(entry => entry.Row).ToList();
            if (rows.Count > 0) yield return new(source.Section, rows);
        }
    }

    #endregion
}
