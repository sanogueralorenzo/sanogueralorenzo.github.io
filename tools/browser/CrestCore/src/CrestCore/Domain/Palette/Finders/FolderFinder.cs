using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The Space's folders that hold a kept tab and whose title or path matches,
/// below a tab that matches as well. Activating one opens its first tab.
internal sealed class FolderFinder : PaletteFinder {
    #region Variables

    protected override int Bias => -50;

    #endregion

    #region Actions - Finding

    internal override IEnumerable<PaletteCandidate> Find(PaletteContext context, PaletteSource source, PaletteQuery query,
        PaletteSuggestions question, bool narrowed) {
        if (context.Space is not { } space) yield break;
        var tree = new FolderTree(space.Folders);
        var byFolder = space.Tabs.Where(tab => tab.Placement.IsDurable && tab.FolderId is not null).ToLookup(tab => tab.FolderId!.Value);
        foreach (var folder in tree.DisplayOrder()) {
            string path = tree.PathTitle(folder.Id);
            int? matched = query.IsEmpty ? 0 : query.Score(folder.Title, path);
            if (matched is not { } score || byFolder[folder.Id].FirstOrDefault() is not { } first) continue;
            int count = byFolder[folder.Id].Count();
            var row = PaletteRow.Of(PaletteRowKind.Folder, folder.Title, Subtitle(count, path), folder.DisplaySymbol, subject: folder.Id,
                tab: first.Id);
            yield return Scored(context, source, row, context.Matched(query, row, score), place: null, PaletteReason.TitleMatch);
        }
    }

    private static string Subtitle(int count, string path) {
        string tabs = count == 1 ? "1 tab" : $"{count} tabs";
        return path.Contains('›') ? $"{path} · {tabs}" : tabs;
    }

    #endregion
}
