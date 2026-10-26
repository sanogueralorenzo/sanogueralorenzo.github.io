namespace CrestCore.Contracts;

/// A password another browser keeps, row `RowNumber` of what it brings, with
/// the name it shows for it, if any.
[HoldsSecrets]
public sealed record ImportedCredential(int RowNumber, string? DisplayName, CredentialOrigin Origin, string Username, string Password) {
    #region Actions - Text

    public override string ToString() {
        var text = new System.Text.StringBuilder("ImportedCredential { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(System.Text.StringBuilder builder) {
        builder.Append($"RowNumber = {RowNumber}, Origin = {Origin}, Username = <redacted>, Password = <redacted>");
        return true;
    }

    #endregion
}
