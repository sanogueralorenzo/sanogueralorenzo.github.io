namespace CrestCore.Contracts;

/// A password the Space already keeps, which an import is compared against.
/// Only a web form's password stands for an account a file imports. Dates are
/// in seconds since 1970.
[HoldsSecrets]
public sealed record ExistingCredential(Guid Id, CredentialOrigin Origin, string Username, bool IsWebForm, double UpdatedAt,
    double? LastUsedAt, string Password) {
    #region Variables

    /// The password's recency, without its account or secret.
    internal CredentialRecord Record => new(Id, Username: null, UpdatedAt, LastUsedAt);

    #endregion

    #region Actions - Recency

    /// The most recent of the passwords the Space keeps for one account, or
    /// null when it keeps none.
    internal static ExistingCredential? MostRecent(IEnumerable<ExistingCredential> saved) {
        ExistingCredential? best = null;
        foreach (var credential in saved) {
            if (!double.IsFinite(credential.UpdatedAt) || credential.LastUsedAt is { } used && !double.IsFinite(used))
                throw new Rejected(new InvalidCredentialDate());
            if (best is null || best.Record.IsLessRecentThan(credential.Record)) best = credential;
        }
        return best;
    }

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new System.Text.StringBuilder("ExistingCredential { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(System.Text.StringBuilder builder) {
        builder.Append($"Id = {Id}, Origin = {Origin}, Username = <redacted>, IsWebForm = {IsWebForm}, Password = <redacted>");
        return true;
    }

    #endregion
}
