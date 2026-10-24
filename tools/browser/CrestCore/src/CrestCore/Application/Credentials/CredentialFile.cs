using System.Text;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// A password file as the core reads it: its format, the passwords its rows
/// hold and the rows it leaves out. The first row names the columns; blank
/// rows are skipped, and the rest count from 2 in the order they appear. A
/// row's site may leave out its scheme, which is then HTTPS.
[HoldsSecrets]
internal sealed record CredentialFile(CredentialFileFormat Format, IReadOnlyList<ImportedCredential> Credentials,
    IReadOnlyList<CredentialRowRejection> Rejections) {
    #region Static Variables

    /// The largest file an import reads, in bytes.
    public const int MaximumBytes = 16 * 1024 * 1024;
    /// The most credential rows a file may hold.
    public const int MaximumRows = 10_000;
    /// The most columns a row may hold.
    public const int MaximumColumns = 64;
    /// The most characters a field may hold.
    public const int MaximumFieldCharacters = 65_536;

    private static readonly CsvReader Reader = new(new CsvLimits(MaximumRows + 1, MaximumColumns, MaximumFieldCharacters));

    #endregion

    #region Actions - Reading

    /// The file `document` holds. Throws `Rejected` with
    /// `InvalidCredentialFile` for one that cannot import at all.
    public static CredentialFile Read(byte[] document) {
        ArgumentNullException.ThrowIfNull(document);
        if (document.Length > MaximumBytes) throw Invalid(CredentialFileFlaw.TooLarge);
        string text;
        try {
            text = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false, throwOnInvalidBytes: true).GetString(document);
        } catch (DecoderFallbackException) {
            throw Invalid(CredentialFileFlaw.NotText);
        }
        IReadOnlyList<IReadOnlyList<string>> rows;
        try {
            rows = Reader.Read(text);
        } catch (CsvException error) {
            throw Invalid(CredentialFileFlaw.Answering(error.Fault));
        }
        rows = [.. rows.Where(row => row.Any(field => !string.IsNullOrWhiteSpace(field)))];
        if (rows.Count == 0) throw Invalid(CredentialFileFlaw.Empty);
        var headers = rows[0].Select(CredentialFileColumn.Normalized).ToArray();
        int site = CredentialFileColumn.Site.Index(headers)!.Value;
        int username = CredentialFileColumn.Username.Index(headers)!.Value;
        int password = CredentialFileColumn.Password.Index(headers)!.Value;
        int? name = CredentialFileColumn.Name.Index(headers);
        var format = CredentialFileFormat.Detected(headers.ToHashSet(StringComparer.Ordinal));
        if (rows.Count - 1 > MaximumRows) throw Invalid(CredentialFileFlaw.TooManyRows);
        if (rows.Count == 1) throw Invalid(CredentialFileFlaw.NoRows);

        var credentials = new List<ImportedCredential>(rows.Count - 1);
        var rejections = new List<CredentialRowRejection>();
        for (int index = 1; index < rows.Count; index++) {
            var row = rows[index];
            int rowNumber = index + 1;
            if (row.Count > headers.Length) {
                rejections.Add(new(rowNumber, CredentialRowFlaw.MalformedRow));
                continue;
            }
            string Field(int column) => column < row.Count ? row[column] : "";
            if (Origin(Field(site).Trim()) is not { } origin) {
                rejections.Add(new(rowNumber, CredentialRowFlaw.InvalidOrigin));
                continue;
            }
            string secret = Field(password);
            if (secret.Length == 0) {
                rejections.Add(new(rowNumber, CredentialRowFlaw.EmptyPassword));
                continue;
            }
            string? displayName = name is { } column && Field(column) is { Length: > 0 } named ? named : null;
            credentials.Add(new(rowNumber, displayName, origin, Field(username), secret));
        }
        return new(format, credentials, rejections);
    }

    /// The HTTP(S) origin `site` names, with HTTPS for a site written without
    /// a scheme, or null for one that is no web address.
    public static CredentialOrigin? Origin(string site) {
        ArgumentNullException.ThrowIfNull(site);
        string spelled = site.Contains("://", StringComparison.Ordinal) ? site : $"https://{site}";
        if (ImportAddress.Read(spelled) is not { } address || WebScheme.Named(address.Scheme) is not { } scheme) return null;
        var origin = new CredentialOrigin(scheme.Name, address.Host.ToLowerInvariant(), address.Port ?? scheme.DefaultPort);
        return origin.IsValid ? origin : null;
    }

    private static Rejected Invalid(CredentialFileFlaw flaw) => new(new InvalidCredentialFile(flaw));

    #endregion

    #region Actions - Text

    public override string ToString() {
        var text = new StringBuilder("CredentialFile { ");
        PrintMembers(text);
        return text.Append(" }").ToString();
    }

    /// The members that name no secret.
    private bool PrintMembers(StringBuilder builder) {
        builder.Append($"Format = {Format.Name}, Credentials = {Credentials.Count}, Rejections = {Rejections.Count}");
        return true;
    }

    #endregion
}
