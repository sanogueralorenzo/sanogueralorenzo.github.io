using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// What each state an engine reports a download in means for its record. The
/// engine contract fixes `EngineDownloadState`'s spelling, so what the core
/// reads in one, and what a report in it does, is declared here, and `Of`
/// reads it.
internal sealed class EngineDownloadStage {
    #region Static Variables

    public static readonly EngineDownloadStage Preparing = new(EngineDownloadState.Preparing, isUnderway: true, settle: SettleWarning);
    public static readonly EngineDownloadStage Downloading = new(EngineDownloadState.Downloading, isUnderway: true, settle: SettleWarning);
    public static readonly EngineDownloadStage AwaitingApproval = new(EngineDownloadState.AwaitingApproval, isUnderway: true,
        settle: AwaitApproval);
    public static readonly EngineDownloadStage Finished = new(EngineDownloadState.Finished, isUnderway: true,
        settle: (engineDownloads, _, turn, download, reported) => {
            engineDownloads.Record(new FinishDownload(download.DownloadId, reported.Received), turn.Changes);
            engineDownloads.End(download, turn.Changes);
        });
    public static readonly EngineDownloadStage Canceled = new(EngineDownloadState.Canceled, isUnderway: false,
        settle: (engineDownloads, _, turn, download, _) => {
            engineDownloads.Record(new CancelDownload(download.DownloadId, EngineDownloads.CanceledMessage), turn.Changes);
            engineDownloads.End(download, turn.Changes);
        });
    public static readonly EngineDownloadStage Failed = new(EngineDownloadState.Failed, isUnderway: false,
        settle: (engineDownloads, _, turn, download, reported) => {
            engineDownloads.Record(new FailDownload(download.DownloadId, EngineDownloads.FailureOf(reported), reported.FailureDetail),
                turn.Changes);
            engineDownloads.End(download, turn.Changes);
        });
    public static readonly EngineDownloadStage Blocked = new(EngineDownloadState.Blocked, isUnderway: false,
        settle: (engineDownloads, _, turn, download, reported) => {
            engineDownloads.Record(new BlockAutomaticDownload(download.DownloadId), turn.Changes);
            download.IsBlocked = true;
            download.ApprovalToken = reported.ApprovalToken;
        });

    public static IReadOnlyList<EngineDownloadStage> All { get; } =
        [Preparing, Downloading, AwaitingApproval, Finished, Canceled, Failed, Blocked];

    #endregion

    #region Variables

    /// The state the engine reports.
    public EngineDownloadState State { get; }

    /// The engine carries the download on, or finished it, rather than
    /// stopping it: a report in such a state takes up a download the person
    /// asked to resume.
    public bool IsUnderway { get; }

    /// What a report in this state does to the live download it reports.
    private readonly Action<EngineDownloads, Engine, EngineDownloadTurn, EngineDownloads.Tracked, EngineDownload> settle;

    #endregion

    #region Constructors

    private EngineDownloadStage(EngineDownloadState state, bool isUnderway,
        Action<EngineDownloads, Engine, EngineDownloadTurn, EngineDownloads.Tracked, EngineDownload> settle) {
        State = state;
        IsUnderway = isUnderway;
        this.settle = settle;
    }

    #endregion

    #region Actions - Lookup

    /// The stage the engine's `reported` state stands for.
    public static EngineDownloadStage Of(EngineDownloadState reported) => All.First(stage => stage.State == reported);

    #endregion

    #region Actions - Reports

    /// Records what `engine` reported, in this state, about the live `download`.
    public void Settle(EngineDownloads engineDownloads, Engine engine, EngineDownloadTurn turn, EngineDownloads.Tracked download,
        EngineDownload reported) =>
        settle(engineDownloads, engine, turn, download, reported);

    // A warning the person or the engine resolved asks nothing more.
    private static void SettleWarning(EngineDownloads engineDownloads, Engine engine, EngineDownloadTurn turn,
        EngineDownloads.Tracked download, EngineDownload reported) =>
        engineDownloads.SettleApproval(download, turn.Changes);

    private static void AwaitApproval(EngineDownloads engineDownloads, Engine engine, EngineDownloadTurn turn,
        EngineDownloads.Tracked download, EngineDownload reported) {
        if (reported.Warning is not { } warning) {
            // An approval with nothing to approve is never kept.
            turn.Issue(engine, new CancelEngineDownload(download.ProfileId, download.EngineId));
            return;
        }
        if (download.ReasonsApproved && DownloadWarning.Of(warning).IsCoveredBy(download.Reasons)) {
            // A warning about what the person already kept asks nothing new.
            if (download.ApprovalToken == reported.ApprovalToken) return;
            download.ApprovalToken = reported.ApprovalToken;
            turn.Issue(engine, new ApproveEngineDownload(download.ProfileId, download.EngineId, reported.ApprovalToken));
            return;
        }
        engineDownloads.Record(new AwaitDownloadApproval(download.DownloadId), turn.Changes);
        if (download.ApprovalToken == reported.ApprovalToken) return;
        engineDownloads.SettleApproval(download, turn.Changes);
        download.ApprovalToken = reported.ApprovalToken;
        var prompt = engineDownloads.Ids.Next();
        engineDownloads.WaitingPrompts[prompt] = new(download, EngineDownloadQuestion.Approval);
        turn.Changes.Publish(new DownloadApprovalAsked(prompt, download.DownloadId, engineDownloads.SpaceOf(reported),
            DownloadFilename.Safe(reported.Filename), download.Reasons, DownloadWarning.Of(warning), download.SourceHost));
    }

    #endregion
}
