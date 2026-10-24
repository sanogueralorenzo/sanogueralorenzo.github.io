namespace CrestCore.Contracts;

#region Queries

/// What the page's credential state does with one observation.
public enum CredentialCaptureAction {
    Ignore,
    RememberUsername,
    DismissFill,
    OfferFill,
    CaptureCandidate,
    OfferSave,
    KeepPending,
    DiscardPending
}

/// Where a fill request or save candidate takes its username from.
public enum CredentialUsernameSource { None, Explicit, Hint }

/// What one validated form message says, without its credential material. The
/// platform keeps the username and password values; the core only learns
/// whether they are present.
public sealed record CredentialFormFacts(CredentialCaptureEvent Event, CredentialOrigin FrameOrigin,
    CredentialOrigin TopLevelOrigin, bool IsMainFrame, bool HasFormId, bool HasUsername, bool HasPassword,
    CredentialPasswordKind? PasswordKind, bool? HasVisiblePasswordField, bool HasFillTarget);

/// Whether a fill may go ahead.
public sealed record CredentialFillDecision(bool IsAllowed);

/// Whether a password field asks for the account's current password or for a
/// new one, as the form classifier reported it.
public enum CredentialPasswordKind { Current, New }

/// The platform's comparison of a candidate against the stored secret of the
/// matched record. The core never receives either password, only this answer.
public sealed record CredentialStoredComparison(Guid Id, bool PasswordMatches);

/// Whether a save candidate is still accepted, or why it is not.
public sealed record CredentialSaveVerdict(CredentialSaveValidity Validity);

/// Whether a save candidate may still be planned or committed.
public enum CredentialSaveValidity { Accepted, InsecureOrigin, Stale }

/// The record a credential rule chose, or null when none qualifies.
public sealed record CredentialChoice(Guid? CredentialId);

#endregion

#region Rejections

/// One question carried more than `Limit` records.
public sealed record CredentialRecordLimitReached(int Limit) : Rejection;

/// Two records in one question share an identity.
public sealed record DuplicateCredential() : Rejection;

/// A credential date or clock reading is not finite.
public sealed record InvalidCredentialDate() : Rejection;

/// A credential origin is not a canonical HTTP(S) origin.
public sealed record InvalidCredentialOrigin() : Rejection;

/// A record an account match needs has no username.
public sealed record InvalidCredentialRecord() : Rejection;

/// A username to match is empty, or a username is longer than its limit.
public sealed record InvalidCredentialUsername() : Rejection;

/// A generated password's length is outside `Minimum` to `Maximum`.
public sealed record InvalidPasswordLength(int Minimum, int Maximum) : Rejection;

/// The platform compared the candidate against a record other than the match.
public sealed record StaleCredentialComparison() : Rejection;

#endregion

#region Models

/// What saving a submitted credential means for the vault.
public enum CredentialSavePlanKind { Create, Update, AlreadyStored }

#endregion
