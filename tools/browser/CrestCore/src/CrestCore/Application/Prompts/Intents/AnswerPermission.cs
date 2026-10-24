using CrestCore.Application;

namespace CrestCore.Contracts;

/// The person answered a site's permission request: whether it `Grants` it,
/// and whether the Space `Remembers` that for the site's later requests, which
/// the core records as the Space's choice in the same step.
public sealed record AnswerPermission(Guid PromptId, bool Grants, bool Remembers) : PromptIntent(PromptId) {
    #region Actions - Prompts

    /// A permission the person answers to remember becomes the Space's choice
    /// in the same step, unless the Space locked while the prompt waited. A
    /// block the Space took while the prompt waited outranks the answer, which
    /// then records nothing.
    internal override void Apply(CrestApp app, ChangeFeed changes) {
        var prompts = app.Prompts;
        var prompt = prompts.Prompt(PromptId);
        if (prompt.Question is not PermissionQuestion permission) throw new Rejected(new PromptAnswerMismatch(PromptId));
        if (prompts.Asking(prompt.PageId) is { } asking && prompts.Decision(asking.SpaceId, permission) is { Denies: true } blocked) {
            prompts.Settle(PromptId, changes);
            app.Issue(prompt.Engine, new SettlePermission(PromptId, Grants: false, blocked.IsPersistent));
            return;
        }
        if (Remembers && prompts.Asking(prompt.PageId) is { } page && permission.Origin.IsValid) {
            var decision = Grants ? SitePermissionDecision.GrantPersistently : SitePermissionDecision.DenyPersistently;
            try {
                app.Device.Handle(new DecideSitePermission(page.SpaceId, permission.Origin, permission.Permission, Detail: null, decision),
                    app.DeviceTurn(changes));
            } catch (Rejected) {
                // A Space that locked keeps nothing; the request is still answered.
            }
        }
        prompts.Settle(PromptId, changes);
        app.Issue(prompt.Engine, new SettlePermission(PromptId, Grants, Remembers));
    }

    #endregion
}
