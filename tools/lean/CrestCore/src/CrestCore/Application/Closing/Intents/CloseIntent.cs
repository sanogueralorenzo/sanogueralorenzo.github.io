using CrestCore.Application;

namespace CrestCore.Contracts;

/// A request to close pages, windows or the app, which the core prepares by
/// asking each page it would close whether it may go. One preparation asks at
/// a time; a close with nothing to ask is ready at once. Each ends with
/// `CloseReady`.
public abstract record CloseIntent(Guid RequestId) : Intent {
    #region Abstract Methods

    /// Runs the intent on the close preparations, publishing what it changed
    /// to `changes` and handing the pages' engines what they are asked.
    internal abstract void Apply(ClosePreparations preparations, ChangeFeed changes, Action<Engine, EngineCommand> issue);

    #endregion

    #region Actions - Routing

    internal sealed override IReadOnlyList<Change> Route(CrestApp app) =>
        app.Turn(changes => app.ClosePreparations.Handle(this, changes, app.Issue));

    #endregion
}
