namespace CrestCore.Contracts;

/// The save plan for one candidate: whether a submitted credential creates a
/// record, updates the most recent record for the same account, or is already
/// stored. `Id` names the existing record an update replaces or an unchanged
/// save leaves alone.
public sealed record CredentialSavePlan(CredentialSavePlanKind Kind, Guid? Id) {
    #region Variables

    /// Only a save that writes to the vault asks the person first.
    public bool RequiresConfirmation => Kind != CredentialSavePlanKind.AlreadyStored;

    #endregion

    #region Actions - Saving

    /// `matchId` is the record `CredentialRecord.Matching` chose. `stored` is
    /// null when there was no match or its secret could not be read; either
    /// way the save creates a record. A comparison for another record is
    /// stale and refused.
    internal static CredentialSavePlan For(Guid? matchId, CredentialStoredComparison? stored) {
        if (stored is not null && stored.Id != matchId) throw new Rejected(new StaleCredentialComparison());
        if (matchId is null || stored is null) return new(CredentialSavePlanKind.Create, null);
        return new(stored.PasswordMatches ? CredentialSavePlanKind.AlreadyStored : CredentialSavePlanKind.Update, matchId);
    }

    #endregion
}
