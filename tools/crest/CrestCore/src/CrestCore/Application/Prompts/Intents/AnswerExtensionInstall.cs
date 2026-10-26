using CrestCore.Application;

namespace CrestCore.Contracts;

/// The person answered whether to install an extension, and whether it
/// installs with its site access withheld.
public sealed record AnswerExtensionInstall(Guid PromptId, bool Accepted, bool WithholdsSiteAccess) : PromptIntent(PromptId) {
    #region Actions - Prompts

    internal override void Apply(CrestApp app, ChangeFeed changes) =>
        app.Prompts.Answer(PromptId, question => question is ExtensionInstallQuestion,
            new SettleExtensionInstall(PromptId, Accepted, WithholdsSiteAccess), changes, app.Issue);

    #endregion
}
