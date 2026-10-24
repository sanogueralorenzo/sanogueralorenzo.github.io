using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The questions waiting on the person. An engine raises each one, and the
/// core answers a site's permission request from its Space's choices when they
/// hold one, publishing only what the person must answer. A prompt settles
/// once: the person answers it, its engine withdraws it, or its page goes. An
/// answer passes to the engine that asked and is never kept, so a credential
/// that answers a server is in no state, change or saved file. Never saved or
/// synced.
internal sealed class Prompts(Device device, Pages pages) {
    #region Types

    /// A prompt waiting on the person: the engine that asked it, the page that
    /// asked or none for one the engine asks itself, and the question, which
    /// says what kind of answer it takes.
    internal sealed record Waiting(Engine Engine, Guid? PageId, object Question);

    #endregion

    #region Variables

    private readonly Dictionary<Guid, Waiting> waiting = [];

    /// The prompts waiting on the person.
    internal Dictionary<Guid, Waiting> WaitingPrompts => waiting;

    #endregion

    #region Actions - Reports

    /// Applies an engine's prompt report. A question from a page the core does
    /// not host on that engine is declined at once, and a permission request
    /// the Space's choices answer is answered without asking.
    public void Report(PromptEvent report, Engine engine, ChangeFeed changes, Action<Engine, EngineCommand> issue) =>
        report.Apply(this, engine, changes, issue);

    /// Answers whether a question waits on the person now. A repeated report
    /// changes nothing; a question from a page the core does not host on that
    /// engine is declined with `declining`, and one `answered` answers from
    /// the page's Space is answered, both at once and without asking.
    internal bool Raised(Engine engine, Guid promptId, Guid? pageId, object question, EngineCommand declining,
        Action<Engine, EngineCommand> issue, Func<Page, EngineCommand?>? answered = null) {
        if (waiting.ContainsKey(promptId)) return false;
        var page = Asking(pageId);
        if (pageId is not null && (page is null || !ReferenceEquals(page.Engine, engine))) {
            issue(engine, declining);
            return false;
        }
        if (page is not null && answered?.Invoke(page) is { } answer) {
            issue(engine, answer);
            return false;
        }
        waiting[promptId] = new(engine, pageId, question);
        return true;
    }

    #endregion

    #region Actions - Pages

    /// Settles each prompt whose page is gone, no longer holds its engine
    /// page, or moved to another engine. The engine that asked closes that
    /// page and what it asked with it, so it hears nothing.
    public void Prune(ChangeFeed changes) {
        ArgumentNullException.ThrowIfNull(changes);
        foreach (var (id, prompt) in waiting.ToArray())
            if (prompt.PageId is not null && (Asking(prompt.PageId) is not { } page || !ReferenceEquals(page.Engine, prompt.Engine)))
                Settle(id, changes);
    }

    #endregion

    #region Actions - Answers

    /// The prompt `promptId` names. Refused with `UnknownPrompt` when no such
    /// prompt waits.
    internal Waiting Prompt(Guid promptId) =>
        waiting.TryGetValue(promptId, out var prompt) ? prompt : throw new Rejected(new UnknownPrompt(promptId));

    /// Settles the prompt `promptId` names and hands the engine that asked
    /// `settlement`, when `answers` is true of its question. Refused with
    /// `UnknownPrompt` when no such prompt waits, and `PromptAnswerMismatch`
    /// for an answer to another kind of question.
    internal void Answer(Guid promptId, Func<object, bool> answers, EngineCommand settlement, ChangeFeed changes,
        Action<Engine, EngineCommand> issue) {
        var prompt = Prompt(promptId);
        if (!answers(prompt.Question)) throw new Rejected(new PromptAnswerMismatch(promptId));
        Settle(promptId, changes);
        issue(prompt.Engine, settlement);
    }

    #endregion

    #region Actions - Rules

    internal void Settle(Guid promptId, ChangeFeed changes) {
        if (waiting.Remove(promptId)) changes.Publish(new PromptSettled(promptId));
    }

    /// What Space `spaceId`'s choices say about `permission`. A capture request
    /// respects a block on either device it asks for, and a combined grant
    /// answers for each device.
    internal SitePermissionDecision Decision(Guid spaceId, PermissionQuestion permission) =>
        (permission.Permission.IsMedia
            ? device.Answer(new CaptureDecision(spaceId, permission.Origin, permission.Permission))
            : device.Answer(new SiteDecision(spaceId, permission.Origin, permission.Permission, Detail: null))).Decision;

    /// The page `pageId` names while the core hosts it and its engine still
    /// holds it, so it may ask; null for none.
    internal Page? Asking(Guid? pageId) =>
        pageId is { } id && pages.Hosted(id) is { Phase.HoldsEnginePage: true } page ? page : null;

    #endregion
}
