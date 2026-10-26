using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Sets the app-wide behavior preferences. The persistent workspace keeps
/// them on this device; they never sync. The translation rules keep to the
/// rule set's own limits, and the palette names each kind of result once.
public sealed record SetAppPreferences(Guid WorkspaceId, AppPreferences Preferences) : SessionIntent(WorkspaceId) {
    #region Actions - Session

    internal override SessionEdit? Edit(NativeSessionAuthority workspace, SessionTurn turn) {
        workspace.RequirePreferenceOwner();
        var preferences = Preferences with {
            TranslationRules = AutomaticTranslationRules.Restore(Preferences.TranslationRules).Rules,
            Palette = Preferences.Palette.Restored()
        };
        return workspace.Preferred(turn.Basis, preferences);
    }

    #endregion
}
