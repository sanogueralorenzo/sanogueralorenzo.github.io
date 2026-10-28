using CrestCore.Application;

namespace CrestCore.Contracts;

/// A question the core answers with a `TAnswer` without changing any state.
public abstract record Query<TAnswer> {
    #region Variables

    /// Whether the app answers it holding its lock, as it does every question
    /// that reads what the app holds. A question that reads files, or state
    /// with a lock of its own such as the cloud transport's, is answered
    /// without it.
    internal virtual bool AnsweredUnderLock => true;

    #endregion

    #region Abstract Methods

    /// The answer, from what `app` holds, or `Rejected` naming the rule that
    /// refuses the question.
    internal abstract TAnswer Answer(CrestApp app);

    #endregion

    #region Actions - Answering

    /// The answer a host without an app gives at the time `context` gives.
    /// Only a question that reads no state, or that names no state to read,
    /// has one; any other only an app answers.
    internal virtual TAnswer AnswerWithoutApp(StandaloneContext context) =>
        throw new ArgumentOutOfRangeException("query", GetType().Name, "Only an app answers this query.");

    #endregion
}
