namespace CrestCore.Contracts;

/// One account an import brings: its site, the username its first row
/// spells, each distinct password its rows offer, how many rows only repeat
/// one of them, the saved password it would change, if any, and the row the
/// import proposes, or null to keep the saved password. A group offers each
/// distinct password once, in row order, and a password the Space keeps for
/// the account, its most recent web form password, is the one the group would
/// change. A group the Space keeps a password for proposes keeping it; any
/// other proposes its first row.
[HoldsSecrets]
public sealed record CredentialImportGroup(CredentialOrigin Origin, string Username, IReadOnlyList<CredentialImportCandidate> Candidates,
    int CollapsedDuplicateRowCount, Guid? ExistingId, int? SuggestedRow) {
    #region Variables

    /// Whether the person must choose: the file offers several passwords, or
    /// one that differs from the saved password.
    [Resolved]
    public bool RequiresChoice => Candidates.Count > 1
        || ExistingId is not null && !(Candidates.Count == 1 && Candidates[0].Effect == CredentialImportEffect.Matches);

    #endregion

    #region Actions - Planning

    /// One account's group from its rows in order, against the password the
    /// Space keeps for it, if any.
    internal static CredentialImportGroup Of(IReadOnlyList<ImportedCredential> rows, ExistingCredential? existing) {
        var candidates = new List<CredentialImportCandidate>();
        foreach (var row in rows) {
            if (candidates.Any(candidate => candidate.Password == row.Password)) continue;
            var effect = existing is null ? CredentialImportEffect.Adds
                : existing.Password == row.Password ? CredentialImportEffect.Matches : CredentialImportEffect.Replaces;
            candidates.Add(new(row.RowNumber, row.Username, row.DisplayName, row.Password, effect));
        }
        return new(rows[0].Origin, rows[0].Username, candidates, rows.Count - candidates.Count, existing?.Id,
            existing is null ? candidates[0].RowNumber : null);
    }

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new System.Text.StringBuilder("CredentialImportGroup { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(System.Text.StringBuilder builder) {
        builder.Append($"Origin = {Origin}, Username = <redacted>, Candidates = {Candidates.Count}, ExistingId = {ExistingId}");
        return true;
    }

    #endregion
}
