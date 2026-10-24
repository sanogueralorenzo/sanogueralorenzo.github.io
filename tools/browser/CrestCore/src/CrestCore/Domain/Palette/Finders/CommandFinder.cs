using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The commands the platform offers in the palette whose title, section or
/// initials match, once two letters are typed or the person narrowed the
/// palette to them, and the few it offers before anything is typed, in the
/// order each command says.
internal sealed class CommandFinder : PaletteFinder {
    #region Actions - Finding

    internal override IEnumerable<PaletteCandidate> Find(PaletteContext context, PaletteSource source, PaletteQuery query,
        PaletteSuggestions question, bool narrowed) {
        if (!narrowed && query.Text.Length < 2) yield break;
        foreach (var command in question.Commands.Where(command => command.Command.OffersInPalette)) {
            int? score = query.IsEmpty ? 0 : query.Score(command.Title, command.SectionTitle) ?? query.Abbreviates(command.Title);
            if (score is not { } matched) continue;
            var row = Row(command);
            yield return Scored(context, source, row, context.Matched(query, row, matched), place: null, fallback: null);
        }
    }

    internal override IReadOnlyList<PaletteRow> Resting(PaletteContext context, PaletteSuggestions question) =>
        [.. question.Commands.Where(command => command.Command.OffersInPalette && command.Command.PaletteRest is not null)
            .OrderBy(command => command.Command.PaletteRest)
            .Take(Math.Min(context.Preferences.Limit(PaletteSource.Actions), PaletteSection.Actions.RestingLimit))
            .Select(Row)];

    private static PaletteRow Row(PaletteCommand command) =>
        PaletteRow.Of(PaletteRowKind.Command, command.Title, command.SectionTitle, command.Command.Symbol, command: command.Command);

    #endregion
}
