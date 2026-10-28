using CrestCore.Application;

namespace CrestCore.Contracts;

/// Something that happened to a page the core may host, which its `PageId`
/// names. The core reads the page once and hands the report to it.
public abstract record PageEvent(Guid PageId) : EngineEvent {
    #region Abstract Methods

    /// Applies the report to the page it names, which the engine that sent it
    /// hosts, publishing what it changed to the turn's `Changes` and handing
    /// the engine commands it causes to the turn's `Issue`.
    internal abstract void Apply(Pages pages, Page page, PageTurn turn);

    #endregion

    #region Actions - Pages

    /// Applies the report `engine` sent. A report about a page the core no
    /// longer knows, or one another engine hosts, changes nothing.
    internal virtual void Apply(Pages pages, Engine engine, PageTurn turn) {
        if (pages.Hosted(PageId) is { } page && ReferenceEquals(page.Engine, engine)) Apply(pages, page, turn);
    }

    #endregion

    #region Actions - Routing

    internal sealed override void Route(CrestApp app, Engine engine, ChangeFeed changes) {
        app.Pages.Report(this, engine, new PageTurn(changes, app.Issue, app.ClosePreparations));
        app.AfterPageReport(changes);
    }

    #endregion
}
