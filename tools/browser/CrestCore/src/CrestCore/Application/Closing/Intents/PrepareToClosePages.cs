using CrestCore.Application;

namespace CrestCore.Contracts;

/// Prepares to close the pages `PageIds` names, in that order.
public sealed record PrepareToClosePages(Guid RequestId, IReadOnlyList<Guid> PageIds) : CloseIntent(RequestId) {
    #region Actions - Closing

    internal override void Apply(ClosePreparations preparations, ChangeFeed changes, Action<Engine, EngineCommand> issue) =>
        preparations.Start(RequestId, quits: false, PageIds, changes, issue);

    #endregion
}
