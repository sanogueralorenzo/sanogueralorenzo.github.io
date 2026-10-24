using System.Text;

using CrestCore.Application;

namespace CrestCore.Contracts;

/// The password file of the Space named `SpaceName`, holding `Credentials`.
/// `FallbackName` is the person's word for a Space, which names the file when
/// the Space's name has no letters or digits. The core keeps nothing of it.
[HoldsSecrets]
[MessageLimit(64 * 1024 * 1024)]
public sealed record CredentialExport(IReadOnlyList<ExportedCredential> Credentials, string SpaceName, string FallbackName)
    : Query<CredentialExportFile> {
    #region Actions - Text

    public override string ToString() {
        var text = new System.Text.StringBuilder("CredentialExport { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    protected override bool PrintMembers(System.Text.StringBuilder builder) {
        builder.Append($"Credentials = {Credentials.Count}, SpaceName = {SpaceName}");
        return true;
    }

    #endregion

    #region Variables

    /// It writes the passwords it holds, not what the app holds.
    internal override bool AnsweredUnderLock => false;

    #endregion

    #region Actions - Answering

    /// The Space's password file.
    internal override CredentialExportFile Answer(CrestApp app) => CredentialExportFile.Of(this);

    #endregion
}
