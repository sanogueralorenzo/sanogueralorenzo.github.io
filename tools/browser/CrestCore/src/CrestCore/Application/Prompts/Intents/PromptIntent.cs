using CrestCore.Application;

namespace CrestCore.Contracts;

/// An answer to a question waiting on the person. A prompt lasts until the
/// person answers it, its engine withdraws it or its page goes, and is never
/// saved or synced.
public abstract record PromptIntent(Guid PromptId) : Intent {
    #region Abstract Methods

    /// Answers the prompt in the area of the app that asked it, publishing
    /// what the answer changed to `changes`. Refused with `UnknownPrompt` for
    /// a prompt that no longer waits, and `PromptAnswerMismatch` for an answer
    /// to another kind of question.
    internal abstract void Apply(CrestApp app, ChangeFeed changes);

    #endregion

    #region Actions - Routing

    internal sealed override IReadOnlyList<Change> Route(CrestApp app) => app.Turn(changes => Apply(app, changes));

    #endregion
}
