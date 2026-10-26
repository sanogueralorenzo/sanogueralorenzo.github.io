using CrestCore.Application;

namespace CrestCore.Contracts;

/// The person answered a script dialog: whether they accepted it, and the text
/// a prompt dialog took.
public sealed record AnswerScriptDialog(Guid PromptId, bool Accepted, string? Text) : PromptIntent(PromptId) {
    #region Actions - Prompts

    internal override void Apply(CrestApp app, ChangeFeed changes) =>
        app.Prompts.Answer(PromptId, question => question is ScriptDialogQuestion,
            new SettleScriptDialog(PromptId, Accepted, Text), changes, app.Issue);

    #endregion
}
