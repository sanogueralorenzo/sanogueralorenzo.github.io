using CrestCore.Application;
using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Where a download's file goes, asked before it begins: `SuggestedFilename`
/// is the engine's name for it, and `ForcesPrompt` asks the person to choose.
/// The download waits for the core's `SettleDownloadDestination`, which first
/// judges its risk from the platform's `Facts` and whether the person started
/// it: a download the person must confirm is asked about before its place.
/// `SourceHost` is the host the file came from, which that question shows; the
/// engine never sends the address itself.
public sealed record EngineDownloadDestinationRequested(Guid PromptId, EngineDownload Download, string SuggestedFilename,
    bool ForcesPrompt, DownloadRiskFacts Facts, bool UserInitiated, string? SourceHost) : EngineDownloadEvent(Download) {
    #region Actions - Downloads

    /// Judges the download's risk, then asks where its file goes, or first
    /// whether to go on with it when the person must confirm it.
    internal override void Apply(EngineDownloads engineDownloads, Engine engine, EngineDownloadTurn turn) {
        if (engineDownloads.Track(engine, Download, turn.Changes, turn.Now) is not { IsLive: true } download
            || engineDownloads.SpaceOf(Download) is not { } space) {
            turn.Issue(engine, new SettleDownloadDestination(PromptId, Path: null));
            return;
        }
        download.SourceHost = SourceHost is { Length: > 0 and <= EngineDownloads.MaximumHostLength } host ? host : null;
        var verdict = engineDownloads.Verdict(Facts, UserInitiated);
        engineDownloads.Record(new AssessDownloadRisk(download.DownloadId, verdict.Assessment), turn.Changes);
        download.Reasons = verdict.Assessment.Reasons;
        download.ReasonsApproved = false;
        if (!verdict.RequiresConfirmation) {
            engineDownloads.AskDestination(download, this, space, turn.Changes);
            return;
        }
        var prompt = engineDownloads.Ids.Next();
        engineDownloads.WaitingPrompts[prompt] = new(download, EngineDownloadQuestion.Risk, this);
        turn.Changes.Publish(new DownloadApprovalAsked(prompt, download.DownloadId, space, DownloadFilename.Safe(SuggestedFilename),
            download.Reasons, Warning: null, download.SourceHost));
    }

    #endregion
}
