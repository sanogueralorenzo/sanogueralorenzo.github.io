using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether a window a page opens, once its engine accepted the request, comes
/// to the front as the selected tab: an ordinary new-window request does, and
/// one made with Command-click or middle-click stays in the background unless
/// Shift is held.
public sealed record OpenedWindowSelection(LinkGesture Gesture) : Query<OpenedWindowSelected> {
    #region Actions - Answering

    /// Whether a window a page opened comes to the front, as its gesture decides.
    internal override OpenedWindowSelected Answer(CrestApp app) {
        var gesture = Gesture;
        bool newTab = gesture.Modifiers.HasFlag(ShortcutModifiers.Command) || gesture.MiddleClick;
        return new(!newTab || gesture.Modifiers.HasFlag(ShortcutModifiers.Shift));
    }

    #endregion
}
