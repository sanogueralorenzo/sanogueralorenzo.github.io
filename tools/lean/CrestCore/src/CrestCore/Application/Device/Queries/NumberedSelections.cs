using CrestCore.Application;

namespace CrestCore.Contracts;

/// Where each numbered command leads in a window: to the stops of the Space it
/// shows, in the order its sidebar shows them (see `SidebarOutline.Stops`), and
/// to the Spaces it may show, in the session's order, which leaves out one
/// being deleted.
public sealed record NumberedSelections(Guid WindowId) : Query<NumberedSelectionList> {
    #region Actions - Answering

    /// Where each numbered command leads in a window: to the stops of the Space
    /// it shows, each to its first tab, and to the Spaces it may show.
    internal override NumberedSelectionList Answer(CrestApp app) {
        var window = app.Device.Opened(WindowId);
        var session = app.Device.Workspace(window.WorkspaceId).Current;
        Guid spaceId;
        lock (app.Device.Gate) spaceId = window.ShownSpaceId;
        IReadOnlyList<Guid> stops = Device.Available(session, spaceId) is { } space
            ? [.. space.Stops().Select(stop => stop.Members[0])] : [];
        var choices = new NumberedChoices(spaceId, stops, [.. Window.Showable(session).Select(showable => showable.Id)]);
        return new([.. ShortcutCommand.All.Select(command => command.Selecting(choices)).OfType<NumberedSelection>()]);
    }

    #endregion
}
