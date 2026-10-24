using System.Text;

using CrestCore.Application;

namespace CrestCore.Contracts;

/// What importing `Credentials`, the passwords another browser keeps, into a
/// Space that keeps `Existing` means, as a browser's own password file would.
/// The core keeps nothing of either.
[HoldsSecrets]
[MessageLimit(64 * 1024 * 1024)]
public sealed record PasswordImportPreview(IReadOnlyList<ImportedCredential> Credentials, IReadOnlyList<ExistingCredential> Existing)
    : Query<CredentialImportPlan> {
    #region Actions - Text

    public override string ToString() {
        var text = new System.Text.StringBuilder("PasswordImportPreview { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    protected override bool PrintMembers(System.Text.StringBuilder builder) {
        builder.Append($"Credentials = {Credentials.Count}, Existing = {Existing.Count}");
        return true;
    }

    #endregion

    #region Variables

    /// It reads the passwords it holds, not what the app holds.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    /// What importing another browser's passwords means, as its own password
    /// file would.
    internal override CredentialImportPlan Answer(CrestApp app) {
        return CredentialImportPlan.For(CredentialFileFormat.Browser, Credentials, [], Existing);
    }

    #endregion
}
