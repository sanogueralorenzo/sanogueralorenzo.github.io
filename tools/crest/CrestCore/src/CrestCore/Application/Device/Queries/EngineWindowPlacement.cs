using CrestCore.Application;

namespace CrestCore.Contracts;

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
