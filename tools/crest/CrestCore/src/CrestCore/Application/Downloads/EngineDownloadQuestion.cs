using CrestCore.Contracts;

namespace CrestCore.Application;

/// What a download's prompt asks: where its file goes, whether to keep a file
/// its engine warned about, or whether to go on with one the core judged
/// dangerous, which holds back the engine's destination request. Each question
/// takes the answers that fit it and rejects the rest.
internal sealed class EngineDownloadQuestion {
    #region Static Variables

    public static readonly EngineDownloadQuestion Destination = new(asksAboutEngineWarning: false, answerApproval: Mismatched,
        answerDestination: (app, answer, prompt, changes) => {
            var engineDownloads = app.EngineDownloads;
            var download = prompt.Download;
            engineDownloads.Settle(answer.PromptId, changes);
            if (answer.Path is { Length: > 0 } path && download.IsLive)
                engineDownloads.Record(new SetDownloadDestination(download.DownloadId, EngineDownloads.FileAddress(path),
                    System.IO.Path.GetFileName(path)), changes);
            app.Issue(download.Engine, new SettleDownloadDestination(answer.PromptId, answer.Path));
        });
    public static readonly EngineDownloadQuestion Approval = new(asksAboutEngineWarning: true,
        answerApproval: (app, answer, prompt, changes) => {
            var engineDownloads = app.EngineDownloads;
            var download = prompt.Download;
            engineDownloads.Settle(answer.PromptId, changes);
            if (answer.Approved) {
                app.Issue(download.Engine, new ApproveEngineDownload(download.ProfileId, download.EngineId, download.ApprovalToken ?? ""));
            } else {
                app.Issue(download.Engine, new CancelEngineDownload(download.ProfileId, download.EngineId));
                engineDownloads.Record(new CancelDownload(download.DownloadId, EngineDownloads.CanceledMessage), changes);
                engineDownloads.End(download, changes);
            }
        }, answerDestination: Mismatched);
    public static readonly EngineDownloadQuestion Risk = new(asksAboutEngineWarning: false,
        answerApproval: (app, answer, prompt, changes) => {
            var engineDownloads = app.EngineDownloads;
            var download = prompt.Download;
            engineDownloads.Settle(answer.PromptId, changes);
            var held = prompt.Held!;
            if (answer.Approved && engineDownloads.SpaceOf(held.Download) is { } space) {
                download.ReasonsApproved = true;
                engineDownloads.AskDestination(download, held, space, changes);
            } else {
                app.Issue(download.Engine, new SettleDownloadDestination(held.PromptId, Path: null));
                engineDownloads.Record(new CancelDownload(download.DownloadId,
                    answer.Approved ? EngineDownloads.CanceledMessage : EngineDownloads.DeclinedMessage), changes);
                engineDownloads.End(download, changes);
            }
        }, answerDestination: Mismatched);

    public static IReadOnlyList<EngineDownloadQuestion> All { get; } = [Destination, Approval, Risk];

    #endregion

    #region Variables

    /// The prompt asks about a warning the engine raised, so it settles when
    /// the engine resolves that warning or raises another.
    public bool AsksAboutEngineWarning { get; }

    private readonly Action<CrestApp, AnswerDownloadApproval, EngineDownloads.Waiting, ChangeFeed> answerApproval;
    private readonly Action<CrestApp, AnswerDownloadDestination, EngineDownloads.Waiting, ChangeFeed> answerDestination;

    #endregion

    #region Constructors

    private EngineDownloadQuestion(bool asksAboutEngineWarning,
        Action<CrestApp, AnswerDownloadApproval, EngineDownloads.Waiting, ChangeFeed> answerApproval,
        Action<CrestApp, AnswerDownloadDestination, EngineDownloads.Waiting, ChangeFeed> answerDestination) {
        AsksAboutEngineWarning = asksAboutEngineWarning;
        this.answerApproval = answerApproval;
        this.answerDestination = answerDestination;
    }

    #endregion

    #region Actions - Answers

    /// Whether the person keeps the file `prompt`, which asks this question, is about.
    public void Answer(CrestApp app, AnswerDownloadApproval answer, EngineDownloads.Waiting prompt, ChangeFeed changes) =>
        answerApproval(app, answer, prompt, changes);

    /// Where the file `prompt`, which asks this question, is about goes.
    public void Answer(CrestApp app, AnswerDownloadDestination answer, EngineDownloads.Waiting prompt, ChangeFeed changes) =>
        answerDestination(app, answer, prompt, changes);

    /// An answer to a question the prompt does not ask.
    private static void Mismatched(CrestApp app, PromptIntent answer, EngineDownloads.Waiting prompt, ChangeFeed changes) =>
        throw new Rejected(new PromptAnswerMismatch(answer.PromptId));

    #endregion
}
