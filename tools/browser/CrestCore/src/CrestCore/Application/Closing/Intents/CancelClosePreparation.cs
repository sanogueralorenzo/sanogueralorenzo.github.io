using CrestCore.Application;

namespace CrestCore.Contracts;

/// Stops the preparation `RequestId` names, which ends not allowed. Nothing
/// happens when another preparation, or none, is under way.
public sealed record CancelClosePreparation(Guid RequestId) : CloseIntent(RequestId) {
    #region Actions - Closing

    internal override void Apply(ClosePreparations preparations, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (preparations.Underway?.RequestId == RequestId) preparations.Finish(allowed: false, changes);
    }

    #endregion
}
