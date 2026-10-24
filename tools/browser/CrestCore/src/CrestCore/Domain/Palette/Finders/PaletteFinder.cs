using CrestCore.Contracts;

namespace CrestCore.Domain;

/// How one kind of result finds and scores its rows: the rows it offers for
/// typed text, the rows it offers before anything is typed, and the rows it
/// adds beside the address or search the text runs. Its signals score each
/// row it finds, in the order they name the row's reason; a kind may start
/// every row lower than another kind that matches as well, and decides whether
/// its rows may lead the palette.
internal abstract class PaletteFinder {
    #region Static Variables

    /// The finder of a kind that finds no rows itself, as search suggestions,
    /// which join after the ranked rows, or the calculator, which leads.
    public static PaletteFinder Nothing { get; } = new Quiet();

    #endregion

    #region Variables

    /// The signals that score this kind's rows, in the order they name a
    /// row's reason.
    protected virtual IReadOnlyList<PaletteSignal> Signals => [PaletteSignal.Learned, PaletteSignal.Match];

    /// What every row of this kind starts from.
    protected virtual int Bias => 0;

    /// Whether a row of this kind may lead the palette as its best match.
    protected virtual bool MayLead => false;

    #endregion

    #region Actions - Finding

    /// The rows the kind offers for `query`, every one when the person
    /// narrowed the palette to it and typed nothing.
    internal virtual IEnumerable<PaletteCandidate> Find(PaletteContext context, PaletteSource source, PaletteQuery query,
        PaletteSuggestions question, bool narrowed) => [];

    /// The rows the kind offers before anything is typed.
    internal virtual IReadOnlyList<PaletteRow> Resting(PaletteContext context, PaletteSuggestions question) => [];

    /// The rows the kind adds beside the address or search typed text runs.
    internal virtual IEnumerable<PaletteRow> Offers(PaletteContext context, PaletteQuery query, PaletteSuggestions question) => [];

    /// The rows the kind adds before anything is typed, above every section.
    internal virtual IEnumerable<PaletteRow> RestingOffers(PaletteContext context, PaletteSuggestions question) => [];

    #endregion

    #region Actions - Scoring

    /// `row` scored by this kind's signals for `evidence`, at `place`, with
    /// the first reason a signal names, else `fallback`.
    protected PaletteCandidate Scored(PaletteContext context, PaletteSource source, PaletteRow row, PaletteEvidence evidence, string? place,
        PaletteReason? fallback) {
        int score = Bias + Signals.Sum(signal => signal.Points(evidence, context));
        var reason = Signals.Select(signal => signal.Names(evidence, context)).FirstOrDefault(named => named is not null) ?? fallback;
        bool leads = MayLead && evidence.Prefixes && Signals.Any(signal => signal.Leads(evidence, context));
        return new(row with { Reason = reason }, source, score, place, leads);
    }

    /// The reason a place gives when no signal names one: that the text
    /// starts its title, else that it matches its address.
    protected static PaletteReason Matching(PaletteEvidence evidence) =>
        evidence.PrefixesTitle ? PaletteReason.TitleMatch : PaletteReason.AddressMatch;

    #endregion

    #region Types

    private sealed class Quiet : PaletteFinder;

    #endregion
}
