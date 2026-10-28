using CrestCore.Contracts;

namespace CrestCore.Application;

/// Answers contract queries: an app answers every query, `StandaloneAnswers`
/// only those that read no state, which a host may ask without an app.
public interface IQueryAnswers {
    #region Abstract Methods

    /// The answer, or `Rejected` naming the rule that refuses the question.
    TAnswer Query<TAnswer>(Query<TAnswer> query);

    #endregion
}
