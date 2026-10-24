using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The tabs the person used most recently before the one the window shows,
/// most recent first, which the palette offers before anything is typed. Where
/// the person orders them first, the tab they were on before leads.
internal sealed class RecentTabFinder : PaletteFinder {
    #region Actions - Finding

    internal override IReadOnlyList<PaletteRow> Resting(PaletteContext context, PaletteSuggestions question) => context.Space is not { } space
        ? []
        : [.. space.Tabs.Where(tab => tab.Id != context.ShownTabId && !tab.IsStartPage).OrderByDescending(tab => tab.LastActivatedAt)
            .Take(context.Preferences.Limit(PaletteSource.RecentTabs))
            .Select(tab => PaletteRow.Of(tab.Placement.PaletteRow, tab.DisplayTitle, PaletteContext.Host(tab.Url) ?? tab.Url ?? "", tab: tab.Id))];

    #endregion
}
