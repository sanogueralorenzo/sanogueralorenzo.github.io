using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The Space's newest history entries that match, ranked by how well they
/// match and how often and recently their page was visited. One that starts
/// with the text and was used enough may lead.
internal sealed class HistoryFinder : PaletteFinder {
    #region Static Variables

    /// The newest history entries a query ranks.
    public const int Scan = 1_500;

    #endregion

    #region Variables

    protected override IReadOnlyList<PaletteSignal> Signals => [PaletteSignal.Learned, PaletteSignal.Usage, PaletteSignal.Match];

    protected override bool MayLead => true;

    #endregion

    #region Actions - Finding

    internal override IEnumerable<PaletteCandidate> Find(PaletteContext context, PaletteSource source, PaletteQuery query,
        PaletteSuggestions question, bool narrowed) {
        if (context.Space is not { } space) yield break;
        foreach (var entry in space.History.Take(Scan)) {
            string title = entry.Title.Length > 0 ? entry.Title : PaletteContext.Host(entry.Url) ?? entry.Url;
            var row = PaletteRow.Of(PaletteRowKind.History, title, entry.Url, subject: entry.Id, address: entry.Url);
            if (context.Evidence(query, row, title, entry.Url, entry: entry) is not { } evidence) continue;
            yield return Scored(context, source, row, evidence, PaletteMemory.Place(entry.Url), Matching(evidence));
        }
    }

    #endregion
}
