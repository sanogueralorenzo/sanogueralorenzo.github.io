using CrestCore.Application;

namespace CrestCore.Contracts;

/// An intent the downloads ledger handles.
public abstract record DownloadIntent : Intent {
    #region Abstract Methods

    /// Runs the intent on the download ledger, publishing each download it
    /// changed or removed. An event that does not apply to a record's phase
    /// publishes nothing.
    internal abstract void Apply(Downloads downloads, ChangeFeed changes);

    #endregion

    #region Actions - Downloads

    /// What the engines do before the ledger runs the intent, for an intent
    /// about a download an engine runs; nothing for any other.
    internal virtual void Before(EngineDownloads engineDownloads, ChangeFeed changes, Action<Engine, EngineCommand> issue) { }

    #endregion

    #region Actions - Routing

    /// An engine's download settles on the engine first, then the ledger
    /// records it.
    internal sealed override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(changes => {
        app.EngineDownloads.Before(this, changes, app.Issue);
        app.Downloads.Handle(this, changes);
    });

    #endregion
}
