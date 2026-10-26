using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

public sealed record PaletteSuggestions(Guid WindowId, string Text, IReadOnlyList<PaletteCommand> Commands,
    IReadOnlyList<PaletteSettingsPage> SettingsPages, IReadOnlyList<string> Remote, PaletteScope? Scope,
    bool AllowsCompletion) : Query<PaletteAnswer> {
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
