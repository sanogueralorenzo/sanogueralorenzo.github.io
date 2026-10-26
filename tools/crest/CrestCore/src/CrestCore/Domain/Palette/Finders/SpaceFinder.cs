using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The workspace's other Spaces whose names or initials match, or every one
/// when the person narrowed the palette to them and typed nothing.
internal sealed class SpaceFinder : PaletteFinder {
    #region Actions - Finding

    internal override IEnumerable<PaletteCandidate> Find(PaletteContext context, PaletteSource source, PaletteQuery query,
        PaletteSuggestions question, bool narrowed) {
        foreach (var other in context.Spaces) {
            string name = other.Settings.Name;
            int? score = query.IsEmpty ? 0 : query.Score(name) ?? query.Abbreviates(name);
            if (score is not { } matched) continue;
            var row = PaletteRow.Of(PaletteRowKind.Space, name, "Space", other.Settings.Symbol, subject: other.Id);
            yield return Scored(context, source, row, context.Matched(query, row, matched), place: null, fallback: null);
        }
    }

    #endregion
}
