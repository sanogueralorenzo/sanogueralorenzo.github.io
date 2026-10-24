using CrestCore.Application;

namespace CrestCore.Contracts;

/// Whether a fill request may put a saved credential or a generated password
/// into a password field of this kind.
public sealed record CredentialFill(CredentialFillSource Source, CredentialPasswordKind PasswordKind)
    : Query<CredentialFillDecision> {
    #region Actions - Answering

    internal override CredentialFillDecision Answer(CrestApp app) {
        return new(Source.Offers(PasswordKind));
    }

    #endregion
}
