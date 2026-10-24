using CrestCore.Application;

namespace CrestCore.Contracts;

/// A document in a page asked for a permission Crest records, which waits for
/// the core's `SettlePermission`. The core answers from the Space's choices
/// when they hold one, and asks the person only when they do not. A capability
/// the system asks about itself is never asked twice: unless the Space blocks
/// it, the request goes on to the system's own question.
public sealed record PermissionRequested(Guid PromptId, Guid PageId, PermissionQuestion Question) : PromptEvent(PromptId) {
    #region Actions - Prompts

    /// A request the Space's choices answer is answered without asking.
    internal override void Apply(Prompts prompts, Engine engine, ChangeFeed changes, Action<Engine, EngineCommand> issue) {
        if (prompts.Raised(engine, PromptId, PageId, Question, new SettlePermission(PromptId, Grants: false, Remembers: false), issue,
                page => Answer(prompts.Decision(page.SpaceId, Question))))
            changes.Publish(new PermissionAsked(PromptId, PageId, Question));
    }

    /// What the Space's `decision` answers without asking the person, or
    /// null when the person must be asked.
    private SettlePermission? Answer(SitePermissionDecision decision) =>
        !decision.Asks ? new(PromptId, decision.Grants, decision.IsPersistent)
        : Question.Permission.IsAskedBySystem ? new(PromptId, Grants: true, Remembers: false)
        : null;

    #endregion
}
