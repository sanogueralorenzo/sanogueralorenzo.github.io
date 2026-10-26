using CrestCore.Application;

namespace CrestCore.Contracts;

/// How Crest answers one HTTP authentication challenge. No username or
/// password crosses: a challenge is its method, whether a proxy asks, and how
/// many attempts the server has refused. Proxy and non-HTTP challenges keep
/// the system's handling. Basic and Digest prompt until the server has refused
/// three attempts, then cancel.
public sealed record ChallengeHandling(AuthenticationMethod Method, bool IsProxy, int PreviousFailureCount)
    : StandaloneQuery<ChallengeHandled> {
    #region Static Variables

    internal const int MaximumCredentialAttempts = 3;

    #endregion

    #region Variables

    internal AuthenticationHandling Handling {
        get {
            ArgumentNullException.ThrowIfNull(Method);
            if (IsProxy || !Method.PromptsForCredentials) return AuthenticationHandling.PerformDefaultHandling;
            return PreviousFailureCount < MaximumCredentialAttempts
                ? AuthenticationHandling.PromptForCredentials : AuthenticationHandling.Cancel;
        }
    }

    #endregion

    #region Actions - Answering

    internal override ChallengeHandled Answer(StandaloneContext context) => new(Handling);

    #endregion
}
