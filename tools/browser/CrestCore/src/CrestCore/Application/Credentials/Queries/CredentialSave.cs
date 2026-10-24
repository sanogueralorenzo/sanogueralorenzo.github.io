using CrestCore.Application;

namespace CrestCore.Contracts;

/// What saving a candidate means for the vault. `MatchId` is the record
/// `CredentialSaveMatch` chose. `Stored` is the platform's comparison of the
/// candidate against that record's secret, or null when there was no match or
/// the secret could not be read.
public sealed record CredentialSave(Guid? MatchId, CredentialStoredComparison? Stored) : Query<CredentialSavePlan> {
    #region Actions - Answering

    internal override CredentialSavePlan Answer(CrestApp app) {
        return CredentialSavePlan.For(MatchId, Stored);
    }

    #endregion
}
