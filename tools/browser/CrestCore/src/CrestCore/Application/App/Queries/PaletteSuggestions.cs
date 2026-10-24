using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// What a window's command palette offers for `Text`: the best match, an
/// address to open or a search to run, the window's tabs, the `Commands` and
/// `SettingsPages` the platform offers there, the Space's pinned and saved
/// tabs, folders, history and archive, and the other Spaces, ranked by how
/// well they match, how often and recently they were used, and what the
/// person chose before for the same text, with an address completion for the
/// text. `Remote` holds the search suggestions the platform fetched from
/// `PaletteAnswer.SuggestionAddress` for the same text, which join the answer
/// after the local rows, or is empty. `Provider` or `Scope` names what
/// the person narrowed the palette to, or both are null. `AllowsCompletion`
/// is false while the field may not complete inline, as after a deletion.
/// `Pasteboard` is the text the platform's pasteboard held when the palette
/// opened, while the person has not yet changed the text it opened with and
/// it may offer it, or null. The palette speaks for the Space
/// the window shows and leaves out the tab it shows; a locked Space offers
/// none of its tabs or history.
public sealed record PaletteSuggestions(Guid WindowId, string Text, IReadOnlyList<PaletteCommand> Commands,
    IReadOnlyList<PaletteSettingsPage> SettingsPages, IReadOnlyList<string> Remote, SearchProvider? Provider, PaletteScope? Scope,
    bool AllowsCompletion, string? Pasteboard) : Query<PaletteAnswer> {
    #region Variables

    /// Only reading what the window shows holds the lock; ranking reads immutable records outside it.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    /// What a window's palette offers. Only reading what the window shows
    /// holds the lock; ranking reads immutable records outside it, so a
    /// palette answering on another thread never holds up the window.
    internal override PaletteAnswer Answer(CrestApp app) {
        Palette palette;
        lock (app.Gate) palette = app.Device.Palette(WindowId, app.Pages.OpensInternalPages, app.Clock.Now);
        return palette.Answer(this);
    }

    #endregion
}
