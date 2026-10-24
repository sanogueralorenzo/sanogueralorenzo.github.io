namespace CrestCore.Contracts;

/// One password an import offers for an account: the first row that brings
/// it, with the username and name that row spells, and what importing it
/// does.
[HoldsSecrets]
public sealed record CredentialImportCandidate(int RowNumber, string Username, string? DisplayName, string Password,
    CredentialImportEffect Effect) {
    #region Actions - Text

    public override string ToString() {
        var text = new System.Text.StringBuilder("CredentialImportCandidate { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(System.Text.StringBuilder builder) {
        builder.Append($"RowNumber = {RowNumber}, Username = <redacted>, Password = <redacted>, Effect = {Effect.Name}");
        return true;
    }

    #endregion
}
