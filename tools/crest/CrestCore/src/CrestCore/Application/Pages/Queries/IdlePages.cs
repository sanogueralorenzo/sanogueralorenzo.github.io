using CrestCore.Application;

namespace CrestCore.Contracts;

#region Types

/// A document that has remained off screen long enough to unload. The final
/// intent checks both stamps again after the engine checks for unsaved work.
public sealed record IdlePageCandidate(Guid PageId, long Documents, DateTimeOffset HiddenSince);
public sealed record IdlePageList(IReadOnlyList<IdlePageCandidate> Pages);

#endregion

/// Background documents eligible for an engine's silent unload check.
public sealed record IdlePages() : Query<IdlePageList> {
    #region Actions - Answering

    internal override IdlePageList Answer(CrestApp app) => new([.. app.Pages.All
        .Where(page => app.Pages.CanAutomaticallyUnload(page, app.Clock.Now))
        .Select(page => new IdlePageCandidate(page.Id, page.Documents, page.HiddenSince!.Value))]);

    #endregion
}
