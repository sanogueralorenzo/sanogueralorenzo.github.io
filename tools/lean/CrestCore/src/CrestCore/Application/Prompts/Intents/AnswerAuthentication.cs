using CrestCore.Application;

namespace CrestCore.Contracts;

/// The person answered a server's request with `Credential`, or cancelled it
/// with none. The core hands the credential to the engine and keeps no copy:
/// it is never in the core's state, a change or anything saved.
public sealed record AnswerAuthentication(Guid PromptId, AuthenticationCredential? Credential) : PromptIntent(PromptId) {
    #region Actions - Prompts

    internal override void Apply(CrestApp app, ChangeFeed changes) =>
        app.Prompts.Answer(PromptId, question => question is AuthenticationQuestion,
            new SettleAuthentication(PromptId, Credential), changes, app.Issue);

    #endregion
}
