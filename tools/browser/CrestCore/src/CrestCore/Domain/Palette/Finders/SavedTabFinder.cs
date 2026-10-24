using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The Space's pinned and saved tabs that match, by their saved address,
/// ranked as open tabs are, with being kept in place of being open. One that
/// starts with the text may lead.
internal sealed class SavedTabFinder : PaletteFinder {
    #region Variables

    protected override IReadOnlyList<PaletteSignal> Signals =>
        [PaletteSignal.Learned, PaletteSignal.Recency, PaletteSignal.Usage, PaletteSignal.Kept, PaletteSignal.Match];

    protected override bool MayLead => true;

    #endregion

    #region Actions - Finding

    internal override IEnumerable<PaletteCandidate> Find(PaletteContext context, PaletteSource source, PaletteQuery query,
        PaletteSuggestions question, bool narrowed) {
        if (context.Space is not { } space) yield break;
        var tree = new FolderTree(space.Folders);
        foreach (var tab in space.Tabs.Where(tab => tab.Placement.IsDurable)) {
            string? address = tab.SavedAddress ?? tab.Url;
            var row = PaletteRow.Of(tab.Placement.PaletteRow, tab.DisplayTitle, Subtitle(tab, tree), tab: tab.Id);
            if (context.Evidence(query, row, tab.DisplayTitle, address, tab.LastActivatedAt, isKept: true) is not { } evidence) continue;
            yield return Scored(context, source, row, evidence, address is null ? null : PaletteMemory.Place(address), Matching(evidence));
        }
    }

    /// Where a saved tab lives and the site it belongs to.
    private static string Subtitle(TabState tab, FolderTree tree) {
        string host = PaletteContext.Host(tab.SavedAddress) ?? PaletteContext.Host(tab.Url) ?? "";
        if (tab.FolderId is not { } folderId) return host;
        string path = tree.PathTitle(folderId);
        return host.Length == 0 ? path : $"{path} · {host}";
    }

    #endregion
}
