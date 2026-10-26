using System.Text;

using CrestCore.Application;

namespace CrestCore.Contracts;

/// What importing the password file `Document` into a Space that keeps
/// `Existing` means. The core reads the file and keeps nothing of it. Throws
/// `Rejected` with `InvalidCredentialFile` for a file it cannot import at all.
[HoldsSecrets]
[MessageLimit(64 * 1024 * 1024)]
public sealed record CredentialImportPreview(byte[] Document, IReadOnlyList<ExistingCredential> Existing) : Query<CredentialImportPlan> {
    #region Actions - Text

    public override string ToString() {
        var text = new System.Text.StringBuilder("CredentialImportPreview { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    protected override bool PrintMembers(System.Text.StringBuilder builder) {
        builder.Append($"Document = <{Document.Length} bytes redacted>, Existing = {Existing.Count}");
        return true;
    }

    #endregion

    #region Variables

    /// It reads the file it holds, not what the app holds.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    /// What importing the password file the query holds means. Throws
    /// `Rejected` with `InvalidCredentialFile` for a file that cannot import.
    internal override CredentialImportPlan Answer(CrestApp app) {
        var file = CredentialFile.Read(Document);
        return CredentialImportPlan.For(file.Format, file.Credentials, file.Rejections, Existing);
    }

    #endregion
}
