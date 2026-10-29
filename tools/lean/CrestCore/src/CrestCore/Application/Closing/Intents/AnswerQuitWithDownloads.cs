using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether the person quits and stops the downloads in progress.
public sealed record AnswerQuitWithDownloads(Guid PromptId, bool Quits) : Intent {
    #region Actions - Closing

    internal override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(changes => {
        if (app.ClosePreparations.QuitPromptId != PromptId) throw new Rejected(new UnknownPrompt(PromptId));
        app.ClosePreparations.Finish(Quits, changes);
    });

    #endregion
}
