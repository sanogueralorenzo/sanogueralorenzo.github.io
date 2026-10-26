using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether a window a page opens, once its engine accepted the request, comes
/// to the front as the selected tab: an ordinary new-window request does, and
/// one made with the new-tab gesture follows this device's link preferences,
/// which Shift reverses.
public sealed record OpenedWindowSelection(LinkGesture Gesture) : Query<OpenedWindowSelected> {
    #region Actions - Answering

    /// Whether a window a page opened comes to the front, as the gesture and
    /// this device's link preferences decide.
    internal override OpenedWindowSelected Answer(CrestApp app) {
        LinkPreferences preferences;
        lock (app.Device.Gate) preferences = app.Device.Links;
        var gesture = Gesture;
        var (_, newTab) = preferences.PeekModifier.Intent(gesture.Modifiers, gesture.MiddleClick);
        return new(!newTab || preferences.FocusesNewTabs != gesture.Modifiers.HasFlag(ShortcutModifiers.Shift));
    }

    #endregion
}
