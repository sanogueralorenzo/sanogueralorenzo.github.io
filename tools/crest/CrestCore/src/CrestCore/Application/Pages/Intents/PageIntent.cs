using CrestCore.Application;

namespace CrestCore.Contracts;

/// An intent about the pages this device hosts: which tab or transient request
/// owns each, and which engine hosts it. The platform names each page with an
/// identity it makes, which does not depend on the engine.
public abstract record PageIntent : Intent {
    #region Abstract Methods

    /// Runs the intent on the pages this device hosts, publishing what it
    /// changed to the turn's `Changes` and handing the engine commands it
    /// causes to the turn's `Issue`.
    internal abstract void Apply(Pages pages, PageTurn turn);

    #endregion

    #region Actions - Routing

    /// A page that opened on an engine no page used, or the last one an
    /// engine hosted, changes what the engines offer.
    internal sealed override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(changes => {
        app.Pages.Handle(this, new PageTurn(changes, app.Issue, app.ClosePreparations));
        app.PublishEngines(changes.Publish);
    });

    #endregion
}
