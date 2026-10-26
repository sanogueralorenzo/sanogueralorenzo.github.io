namespace CrestCore.Contracts;

/// The capture rules' answer for one observation. `ClearsUsernameHint` asks
/// the caller to forget a remembered username that no longer applies.
/// `AnchorsToField` says whether a fill prompt may point at the reported field.
/// `CandidateLifetime` and `UsernameHintLifetime` are the seconds a captured
/// candidate and a remembered username stay usable.
public sealed record CredentialCaptureDecision(CredentialCaptureAction Action, CredentialUsernameSource UsernameSource,
    bool ClearsUsernameHint, bool IsCrossOriginFrame, bool AnchorsToField, double CandidateLifetime,
    double UsernameHintLifetime) {
    #region Actions - Capture

    /// A decision carrying the lifetimes the caller schedules expiry with.
    internal static CredentialCaptureDecision For(CredentialCaptureAction action,
        CredentialUsernameSource usernameSource = CredentialUsernameSource.None, bool clearsUsernameHint = false,
        bool isCrossOriginFrame = false, bool anchorsToField = false) =>
        new(action, usernameSource, clearsUsernameHint, isCrossOriginFrame, anchorsToField, CredentialPendingCandidate.Lifetime,
            CredentialUsernameHint.Lifetime);

    #endregion
}
