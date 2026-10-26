using CrestCore.Application;

namespace CrestCore.Contracts;

/// A download the engine runs, which the core records in its download ledger.
public abstract record EngineDownloadEvent(EngineDownload Download) : EngineEvent {
    #region Abstract Methods

    /// Applies what `engine` reported about the download to the ledger,
    /// publishing what it changed and handing the engine commands it causes
    /// to the turn.
    internal abstract void Apply(EngineDownloads engineDownloads, Engine engine, EngineDownloadTurn turn);

    #endregion

    #region Actions - Routing

    internal sealed override void Route(CrestApp app, Engine engine, ChangeFeed changes) =>
        app.EngineDownloads.Report(this, engine, new EngineDownloadTurn(changes, app.Issue, app.Clock.Now));

    #endregion
}
