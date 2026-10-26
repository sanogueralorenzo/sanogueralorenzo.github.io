using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The Space's archived tabs that match, newest first, below a live tab that
/// matches as well. Activating one reopens it.
internal sealed class ArchiveFinder : PaletteFinder {
    #region Variables

    protected override IReadOnlyList<PaletteSignal> Signals => [PaletteSignal.Match];

    protected override int Bias => -100;

    #endregion

    #region Actions - Finding

    internal override IEnumerable<PaletteCandidate> Find(PaletteContext context, PaletteSource source, PaletteQuery query,
        PaletteSuggestions question, bool narrowed) {
        if (context.Space is not { } space) yield break;
        foreach (var archived in space.ArchivedTabs.OrderByDescending(archived => archived.ArchivedAt)) {
            var tab = archived.Tab;
            string? address = tab.SavedAddress ?? tab.Url;
            var row = PaletteRow.Of(PaletteRowKind.ArchivedTab, tab.DisplayTitle, PaletteContext.Host(address) ?? "", subject: tab.Id);
            if (context.Evidence(query, row, tab.DisplayTitle, address) is not { } evidence) continue;
            yield return Scored(context, source, row, evidence, place: null, Matching(evidence));
        }
    }

    #endregion
}
