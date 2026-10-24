using CrestCore.Application;

namespace CrestCore.Contracts;

/// An engine download started, progressed, finished or failed. The core
/// records it in the download ledger, in the Space its page or profile belongs
/// to, and asks the person to keep a file the engine warned about.
public sealed record EngineDownloadChanged(EngineDownload Download) : EngineDownloadEvent(Download) {
    #region Actions - Downloads

    internal override void Apply(EngineDownloads engineDownloads, Engine engine, EngineDownloadTurn turn) {
        if (engineDownloads.Track(engine, Download, turn.Changes, turn.Now) is not { } download) {
            turn.Issue(engine, new CancelEngineDownload(Download.ProfileId, Download.DownloadId));
            return;
        }
        if (download.ResumeRequested) {
            download.ResumeRequested = false;
            if (!download.IsLive && EngineDownloadStage.Of(Download.State).IsUnderway) engineDownloads.Resume(download, turn.Changes);
        }
        if (!download.IsLive) return;
        download.LastReport = Download;
        if (Download.Path is { Length: > 0 } path) {
            var destination = new SetDownloadDestination(download.DownloadId, EngineDownloads.FileAddress(path), Path.GetFileName(path));
            engineDownloads.Record(destination, turn.Changes);
        }
        var sample = new DownloadProgress(download.Estimator, Download.Received, Download.Total,
            Download.Total > 0 ? (double)Download.Received / Download.Total : 0, Download.Paused, EngineDownloads.Uptime);
        if (engineDownloads.Sample(sample) is { } reading) {
            download.Estimator = reading.Estimator;
            engineDownloads.Record(new RecordDownloadTransfer(download.DownloadId, reading.Telemetry, reading.Progress), turn.Changes);
        }
        EngineDownloadStage.Of(Download.State).Settle(engineDownloads, engine, turn, download, Download);
        engineDownloads.SetControls(download, Download, turn.Changes);
    }

    #endregion
}
