using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A row for each scope whose keyword starts with what was typed, where the
/// kind it narrows to is offered; Tab, a space after the whole keyword, or
/// the row enters it.
internal sealed class ScopeFinder : PaletteFinder {
    #region Actions - Finding

    internal override IEnumerable<PaletteRow> Offers(PaletteContext context, PaletteQuery query, PaletteSuggestions question) {
        if (!query.Text.StartsWith('@')) return [];
        return PaletteScope.All.Where(scope => context.Preferences.Offers(scope.Source)
                && scope.Keyword.StartsWith(query.Text, StringComparison.OrdinalIgnoreCase))
            .Select(scope => PaletteRow.Of(PaletteRowKind.Scope, $"Search {scope.Title}", scope.Keyword, scope.Symbol, scope: scope));
    }

    #endregion
}
