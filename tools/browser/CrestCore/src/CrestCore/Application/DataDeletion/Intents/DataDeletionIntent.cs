using CrestCore.Application;

namespace CrestCore.Contracts;

/// A request to erase what the engines keep for a profile, which the core asks
/// of every registered engine, started or not. It ends with `DataDeleted`.
public abstract record DataDeletionIntent(Guid RequestId) : Intent {
    #region Abstract Methods

    /// Asks every registered engine for its part of the deletion, handing it
    /// to `issue`. A deletion no engine is asked about ends at once, publishing
    /// to `changes`.
    internal abstract void Apply(DataDeletions deletions, ChangeFeed changes, Action<Engine, EngineCommand> issue);

    #endregion

    #region Actions - Routing

    internal sealed override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.DataDeletions.Handle(this, changes, app.Issue));

    #endregion
}
