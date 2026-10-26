using CrestCore.Application;

namespace CrestCore.Contracts;

/// A question the core answers from the question alone, reading no state, so
/// a host may ask it before it has an app or from code that holds none.
public abstract record StandaloneQuery<TAnswer> : Query<TAnswer> {
    #region Abstract Methods

    /// The answer, from the question alone and the time `context` gives, or
    /// `Rejected` naming the rule that refuses it.
    internal abstract TAnswer Answer(StandaloneContext context);

    #endregion

    #region Actions - Answering

    /// An app answers it as a host without one does.
    internal sealed override TAnswer Answer(CrestApp app) => Answer(new StandaloneContext(DateTimeOffset.UtcNow));

    /// A host without an app answers it from the question alone.
    internal sealed override TAnswer AnswerWithoutApp(StandaloneContext context) => Answer(context);

    #endregion
}
