using CrestCore.Application;

namespace CrestCore.Contracts;

/// An extension install the window `WindowId` started needs the person's
/// approval, which waits for the core's `SettleExtensionInstall`.
public sealed record ExtensionInstallRequested(Guid PromptId, Guid WindowId, ExtensionInstallQuestion Question) : PromptEvent(PromptId) {
    #region Actions - Prompts

    internal override void Apply(Prompts prompts, Engine engine, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        var declining = new SettleExtensionInstall(PromptId, Accepted: false, WithholdsSiteAccess: false);
        if (prompts.Raised(engine, PromptId, pageId: null, Question, declining, issue))
            changes.Publish(new ExtensionInstallAsked(PromptId, WindowId, Question));
    }

    #endregion
}
