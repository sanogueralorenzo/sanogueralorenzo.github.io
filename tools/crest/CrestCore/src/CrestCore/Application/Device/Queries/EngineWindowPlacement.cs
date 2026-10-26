using CrestCore.Application;

namespace CrestCore.Contracts;

/// Where the tabs of a browser window an engine created for the profile
/// `ProfileId` go, over this device's windows as the platform stacks them,
/// frontmost first (`WindowIds`). They belong to the one Space that holds the
/// profile, and are declined when no Space or more than one holds it, when
/// that Space is locked or being deleted, or when it is neither the person's
/// own nor a private one. A private Space's tabs join the private window while
/// it is stacked, and are declined once it is not. The person's own join the
/// frontmost window over the persistent session, unless the engine asked for
/// a window of its own (`OwnWindow`), as an extension's `chrome.windows.create`
/// does for a normal window, or none is open: then a new window opens.
public sealed record EngineWindowPlacement(Guid ProfileId, bool OwnWindow, IReadOnlyList<Guid> WindowIds)
    : Query<EngineWindowPlace> {
    #region Actions - Answering

    internal override EngineWindowPlace Answer(CrestApp app) {
        var declined = new EngineWindowPlace(null, null, OpensWindow: false);
        if (app.Device.OnlyShowableSpaceOf(ProfileId) is not var (ownerId, spaceId)) return declined;
        if (app.Device.Attached(ownerId)?.Kind.IsPrivate == true)
            return app.Device.FrontWindowOver(ownerId, WindowIds) is { } host ? new(host, spaceId, OpensWindow: false) : declined;
        if (app.Device.Persistent()?.WorkspaceId != ownerId) return declined;
        if (!OwnWindow && app.Device.FrontWindow(WindowIds) is { } front) return new(front.Id, spaceId, OpensWindow: false);
        return new(app.Ids.Next(), spaceId, OpensWindow: true);
    }

    #endregion
}
