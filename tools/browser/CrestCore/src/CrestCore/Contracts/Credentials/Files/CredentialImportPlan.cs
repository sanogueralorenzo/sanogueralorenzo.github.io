using System.Globalization;

namespace CrestCore.Contracts;

/// What importing a password file, or another browser's passwords, into a
/// Space means: the file's format, each account it brings in order of site
/// and username, the rows it leaves out and the rows it warns about. Rows for
/// one account, the same site and a username that differs at most in case,
/// form one group, and groups run in order of site, then username.
[HoldsSecrets]
public sealed record CredentialImportPlan(CredentialFileFormat Format, IReadOnlyList<CredentialImportGroup> Groups,
    IReadOnlyList<CredentialRowRejection> Rejections, IReadOnlyList<CredentialRowWarning> Warnings) {
    #region Static Variables

    /// Compares usernames as one account: ignoring case.
    private static readonly StringComparer Usernames = StringComparer.InvariantCultureIgnoreCase;

    #endregion

    #region Variables

    /// How many of the file's rows import or repeat a password that does.
    [Resolved]
    public int ValidRowCount => Groups.Sum(group => group.Candidates.Count + group.CollapsedDuplicateRowCount);

    #endregion

    #region Actions - Planning

    /// The plan for `credentials`, read as `format` with `rejections` already
    /// left out, against `existing`. A credential whose site is no web
    /// address, or whose password is empty, is left out too.
    internal static CredentialImportPlan For(CredentialFileFormat format, IReadOnlyList<ImportedCredential> credentials,
        IReadOnlyList<CredentialRowRejection> rejections, IReadOnlyList<ExistingCredential> existing) {
        ArgumentNullException.ThrowIfNull(format);
        ArgumentNullException.ThrowIfNull(credentials);
        ArgumentNullException.ThrowIfNull(rejections);
        ArgumentNullException.ThrowIfNull(existing);
        if (existing.Select(saved => saved.Id).Distinct().Count() != existing.Count) throw new Rejected(new DuplicateCredential());
        var left = rejections.ToList();
        var valid = new List<ImportedCredential>(credentials.Count);
        foreach (var credential in credentials) {
            if (!credential.Origin.IsValid) left.Add(new(credential.RowNumber, CredentialRowFlaw.InvalidOrigin));
            else if (credential.Password.Length == 0) left.Add(new(credential.RowNumber, CredentialRowFlaw.EmptyPassword));
            else valid.Add(credential);
        }
        var saved = existing.Where(credential => credential.IsWebForm).ToLookup(credential => Account(credential.Origin,
            credential.Username));
        var groups = valid.GroupBy(credential => Account(credential.Origin, credential.Username))
            .Select(rows => CredentialImportGroup.Of([.. rows.OrderBy(row => row.RowNumber)], ExistingCredential.MostRecent(saved[rows.Key])))
            .OrderBy(group => group.Origin.Spelling, StringComparer.Ordinal)
            .ThenBy(group => group.Username, Usernames)
            .ToArray();
        var warnings = valid.Where(credential => !credential.Origin.IsSecure)
            .Select(credential => new CredentialRowWarning(credential.RowNumber, CredentialRowCaution.InsecureOrigin)).ToArray();
        return new(format, groups, [.. left.OrderBy(rejection => rejection.RowNumber)], warnings);
    }

    /// The key an account's rows share: its site and its username in one case.
    private static (CredentialOrigin Origin, string Username) Account(CredentialOrigin origin, string username) =>
        (origin, username.ToUpper(CultureInfo.InvariantCulture).ToLower(CultureInfo.InvariantCulture));

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new System.Text.StringBuilder("CredentialImportPlan { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(System.Text.StringBuilder builder) {
        builder.Append($"Format = {Format.Name}, Groups = {Groups.Count}, Rejections = {Rejections.Count}, Warnings = {Warnings.Count}");
        return true;
    }

    #endregion
}
