namespace CrestCore.Contracts;

/// A saved password a Space exports, with the name it shows, if any, and the
/// note the file keeps beside it.
[HoldsSecrets]
public sealed record ExportedCredential(Guid Id, CredentialOrigin Origin, string Username, string? DisplayName, string Password,
    string Note) {
    #region Actions - Text

    public override string ToString() {
        var text = new System.Text.StringBuilder("ExportedCredential { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(System.Text.StringBuilder builder) {
        builder.Append($"Id = {Id}, Origin = {Origin}, Username = <redacted>, Password = <redacted>");
        return true;
    }

    #endregion
}
