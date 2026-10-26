using CrestCore.Application;

namespace CrestCore.Contracts;

/// The current Space of the frontmost regular window, or the most recent
/// regular window to reopen. Private and borrowed workspaces never receive
/// external opens. A Space being deleted cannot receive one either.
public sealed record ExternalOpenDestination(IReadOnlyList<Guid> WindowIds) : Query<ExternalOpenPlacement> {
    #region Actions - Answering

    internal override ExternalOpenPlacement Answer(CrestApp app) {
        if (app.Device.Persistent() is not (_, var authority)) return new(null, null, OpensWindow: false);
        var session = authority.Current;
        var front = app.Device.FrontWindow(WindowIds);
        Guid opening;
        lock (app.Device.Gate) opening = front?.Id ?? app.Device.WindowToOpen(app.Ids);
        var preferred = front?.ShownSpaceId ?? app.Device.OpeningSpace(opening, session);
        var space = session.Spaces.FirstOrDefault(space => space.Id == preferred && !authority.IsDeleting(space.Id))
            ?? session.Spaces.FirstOrDefault(space => !authority.IsDeleting(space.Id));
        return space is null ? new(null, null, OpensWindow: false) : new(opening, space.Id, OpensWindow: front is null);
    }

    #endregion
}
