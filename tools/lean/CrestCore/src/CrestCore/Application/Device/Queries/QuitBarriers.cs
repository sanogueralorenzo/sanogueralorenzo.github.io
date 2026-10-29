using CrestCore.Application;

namespace CrestCore.Contracts;

/// Active profile erasures a quit would interrupt; pending, idle deletions do not block it.
public sealed record QuitBarriers : Query<QuitBarrierList> {
    internal override QuitBarrierList Answer(CrestApp app) => new(app.Device.SpacesBeingDeleted(app.DataDeletions.Erasing));
}

public sealed record QuitBarrierList(IReadOnlyList<Guid> SpaceIds);
