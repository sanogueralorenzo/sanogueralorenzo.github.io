using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The Space's open tabs that match, other than the one the window shows,
/// ranked by how well they match, how often their page and how recently the
/// tab was used, and whether the person prefers open tabs. One that starts
/// with the text and was used enough may lead.
internal sealed class OpenTabFinder : PaletteFinder {
    #region Variables

    protected override IReadOnlyList<PaletteSignal> Signals =>
        [PaletteSignal.Learned, PaletteSignal.Recency, PaletteSignal.Usage, PaletteSignal.OpenTab, PaletteSignal.Match];

    protected override bool MayLead => true;

    #endregion

    #region Actions - Finding

    internal override IEnumerable<PaletteCandidate> Find(PaletteContext context, PaletteSource source, PaletteQuery query,
        PaletteSuggestions question, bool narrowed) {
        if (context.Space is not { } space) yield break;
        foreach (var tab in space.Tabs.Where(tab => tab.Id != context.ShownTabId && !tab.IsStartPage && !tab.Placement.IsDurable)) {
            var row = PaletteRow.Of(PaletteRowKind.Tab, tab.DisplayTitle, PaletteContext.Host(tab.Url) ?? tab.Url ?? "", tab: tab.Id);
            if (context.Evidence(query, row, tab.DisplayTitle, tab.Url, tab.LastActivatedAt, isOpen: true) is not { } evidence) continue;
            yield return Scored(context, source, row, evidence, tab.Url is null ? null : PaletteMemory.Place(tab.Url), Matching(evidence));
        }
    }

    #endregion
}
