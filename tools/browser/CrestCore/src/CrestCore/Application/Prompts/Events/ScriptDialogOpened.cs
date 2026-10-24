using CrestCore.Application;

namespace CrestCore.Contracts;

/// A document in a page opened a script dialog, which waits for the core's
/// `SettleScriptDialog`.
public sealed record ScriptDialogOpened(Guid PromptId, Guid PageId, ScriptDialogQuestion Question) : PromptEvent(PromptId) {
    #region Actions - Prompts

    internal override void Apply(Prompts prompts, Engine engine, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (prompts.Raised(engine, PromptId, PageId, Question, new SettleScriptDialog(PromptId, Accepted: false, Text: null), issue))
            changes.Publish(new ScriptDialogAsked(PromptId, PageId, Question));
    }

    #endregion
}
