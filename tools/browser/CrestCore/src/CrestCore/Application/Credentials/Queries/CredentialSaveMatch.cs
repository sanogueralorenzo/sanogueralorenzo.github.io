using CrestCore.Application;

namespace CrestCore.Contracts;

/// The most recent record for the same account as `Username`, compared after
/// canonical composition and ignoring case. Every record carries its username;
/// no password crosses.
public sealed record CredentialSaveMatch(string Username, IReadOnlyList<CredentialRecord> Records) : Query<CredentialChoice> {
    #region Actions - Answering

    internal override CredentialChoice Answer(CrestApp app) {
        return new(CredentialRecord.Matching(Username, Records)?.Id);
    }

    #endregion
}
