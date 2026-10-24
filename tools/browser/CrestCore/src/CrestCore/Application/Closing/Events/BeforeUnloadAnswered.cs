using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether a page the core asked may go.
public sealed record BeforeUnloadAnswered(Guid PageId, bool Proceeds) : EngineEvent {
    #region Actions - Routing

    /// The preparation under way goes on to the next page, or ends not
    /// allowed when the page asks to stay. An answer the preparation no longer
    /// waits for, or from an engine that no longer hosts the page, changes
    /// nothing.
    internal override void Route(CrestApp app, Engine engine, ChangeFeed changes) {
        var preparations = app.ClosePreparations;
        if (preparations.Underway is not { } underway || underway.Awaiting != PageId
            || app.Pages.Hosted(PageId) is { } page && !ReferenceEquals(page.Engine, engine))
            return;
        underway.Awaiting = null;
        if (Proceeds) preparations.Advance(changes, app.Issue);
        else preparations.Finish(allowed: false, changes);
        app.AfterPageReport(changes);
    }

    #endregion
}
