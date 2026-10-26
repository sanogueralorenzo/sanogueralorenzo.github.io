using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The settings pages the platform offers whose title, terms or initials
/// match, once two letters are typed.
internal sealed class SettingsPageFinder : PaletteFinder {
    #region Actions - Finding

    internal override IEnumerable<PaletteCandidate> Find(PaletteContext context, PaletteSource source, PaletteQuery query,
        PaletteSuggestions question, bool narrowed) {
        if (query.Text.Length < 2) yield break;
        foreach (var page in question.SettingsPages) {
            if ((query.Score(page.Title, page.Terms) ?? query.Abbreviates(page.Title)) is not { } score) continue;
            var row = PaletteRow.Of(PaletteRowKind.SettingsPage, page.Title, "Settings", page: page.Name);
            yield return Scored(context, source, row, context.Matched(query, row, score), place: null, fallback: null);
        }
    }

    #endregion
}
