using CrestCore.Contracts;

namespace CrestCore.Application;

#region Types

/// What a question that reads no state reads besides itself: the time it is
/// answered at.
internal sealed record StandaloneContext(DateTimeOffset Now);

#endregion

/// The queries that read no state: whether two addresses name one page, the
/// addresses history keeps for others, how translation languages match, which
/// translation rule applies, what an address typed outside any workspace
/// loads, how a launch treats the person's data, the session a seed opens
/// as, branding as a Space keeps it, what a page surface shows, which
/// addresses and schemes Crest takes from outside, how it answers an
/// authentication challenge, how page media sessions order, what a site's
/// origin, notification request, blocked popup or automatic download leads
/// to, and the capacities the core enforces. A host asks them before it has
/// an app, or from code that holds none; an app answers them the same way.
public sealed class StandaloneAnswers : IQueryAnswers {
    #region Actions - Queries

    /// The answer to a question that reads no state, and to an address that
    /// names no workspace, which resolves by the default rules. Throws for any
    /// other question, which only an app answers.
    public TAnswer Query<TAnswer>(Query<TAnswer> query) {
        ArgumentNullException.ThrowIfNull(query);
        return query.AnswerWithoutApp(new StandaloneContext(DateTimeOffset.UtcNow));
    }

    #endregion
}
