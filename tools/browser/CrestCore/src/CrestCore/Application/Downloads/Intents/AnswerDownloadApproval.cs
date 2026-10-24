using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether the person keeps a file the engine warned about. A file not kept
/// is cancelled.
public sealed record AnswerDownloadApproval(Guid PromptId, bool Approved) : PromptIntent(PromptId) {
    #region Actions - Downloads

    /// A file the person does not keep is cancelled at once. One they go on
    /// with despite the core's reasons is then asked where it goes, and one
    /// they keep despite its engine's warning goes on.
    internal override void Apply(CrestApp app, ChangeFeed changes) {
        var prompt = app.EngineDownloads.Prompt(PromptId);
        prompt.Question.Answer(app, this, prompt, changes);
    }

    #endregion
}
