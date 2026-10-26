using CrestCore.Application;

namespace CrestCore.Contracts;

/// Where the file of a download goes, as the platform resolved it or the person
/// chose it, or none to cancel the download.
public sealed record AnswerDownloadDestination(Guid PromptId, string? Path) : PromptIntent(PromptId) {
    #region Actions - Downloads

    /// A file going somewhere names the record's file.
    internal override void Apply(CrestApp app, ChangeFeed changes) {
        var prompt = app.EngineDownloads.Prompt(PromptId);
        prompt.Question.Answer(app, this, prompt, changes);
    }

    #endregion
}
