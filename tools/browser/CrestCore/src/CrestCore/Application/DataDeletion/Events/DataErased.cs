using CrestCore.Application;

namespace CrestCore.Contracts;

/// An erasure the core asked for ended: `Erased` says nothing it covered is
/// left.
public sealed record DataErased(Guid ErasureId, bool Erased) : EngineEvent {
    #region Actions - Routing

    /// One engine answered its part of a deletion; an answer from another
    /// engine, or to an erasure nobody waits on, changes nothing.
    internal override void Route(CrestApp app, Engine engine, ChangeFeed changes) {
        var deletions = app.DataDeletions;
        if (!deletions.ByErasure.TryGetValue(ErasureId, out var deletion) || !ReferenceEquals(deletion.Waiting[ErasureId], engine)) return;
        deletions.ByErasure.Remove(ErasureId);
        deletion.Waiting.Remove(ErasureId);
        deletion.Erased &= Erased;
        if (deletion.Waiting.Count == 0) deletions.Finish(deletion, changes);
    }

    #endregion
}
