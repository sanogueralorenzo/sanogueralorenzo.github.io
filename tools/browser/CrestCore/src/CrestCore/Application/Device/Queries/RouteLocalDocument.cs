using CrestCore.Application;

namespace CrestCore.Contracts;

/// Where a document another app hands Crest opens, over this device's windows
/// as the platform stacks them, frontmost first (`WindowIds`). A document has
/// no host for the link rules to route on, so it opens in the Space on screen:
/// the one the frontmost window over the persistent session shows, or with
/// none open, the one the window a person would open shows, which opens. The
/// platform unlocks a locked Space before it opens the document there.
public sealed record RouteLocalDocument(IReadOnlyList<Guid> WindowIds) : Query<LocalDocumentPlacement> {
    #region Actions - Answering

    internal override LocalDocumentPlacement Answer(CrestApp app) {
        if (app.Device.Persistent() is not (_, var authority)) return new(null, null, OpensWindow: false);
        var session = authority.Current;
        if (app.Device.FrontWindow(WindowIds) is { } front)
            return new(front.Id, Device.Available(session, front.ShownSpaceId)?.Id, OpensWindow: false);
        Guid opening;
        lock (app.Device.Gate) opening = app.Device.WindowToOpen(app.Ids);
        return app.Device.OpeningSpace(opening, session) is { } space
            ? new(opening, space, OpensWindow: true)
            : new(null, null, OpensWindow: false);
    }

    #endregion
}
