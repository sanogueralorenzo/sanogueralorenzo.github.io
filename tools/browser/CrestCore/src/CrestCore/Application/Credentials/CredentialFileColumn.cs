using CrestCore.Contracts;

namespace CrestCore.Application;

/// A column a password file names under one of several headers, as each
/// browser and password manager spells it, compared once normalized. A
/// required column the file lacks, or names twice, keeps the file from
/// importing.
internal sealed class CredentialFileColumn {
    #region Static Variables

    public static readonly CredentialFileColumn Site = new(headers: ["url", "origin", "website", "login_uri"],
        missing: CredentialFileFlaw.NoSiteColumn, repeated: CredentialFileFlaw.SeveralSiteColumns);
    public static readonly CredentialFileColumn Username = new(headers: ["username", "user", "login", "email", "login_username"],
        missing: CredentialFileFlaw.NoUsernameColumn, repeated: CredentialFileFlaw.SeveralUsernameColumns);
    public static readonly CredentialFileColumn Password = new(headers: ["password", "pass", "login_password"],
        missing: CredentialFileFlaw.NoPasswordColumn, repeated: CredentialFileFlaw.SeveralPasswordColumns);
    /// The name a row gives its account; a file may leave it out, and the
    /// first matching header wins.
    public static readonly CredentialFileColumn Name = new(headers: ["name", "title"], missing: null, repeated: null);

    #endregion

    #region Variables

    private readonly IReadOnlySet<string> headers;
    /// Why a file lacking the column cannot import, or null for a column a
    /// file may leave out.
    private readonly CredentialFileFlaw? missing;
    /// Why a file naming the column twice cannot import, or null for one
    /// whose first header wins.
    private readonly CredentialFileFlaw? repeated;

    #endregion

    #region Constructors

    private CredentialFileColumn(IReadOnlyList<string> headers, CredentialFileFlaw? missing, CredentialFileFlaw? repeated) {
        this.headers = headers.ToHashSet(StringComparer.Ordinal);
        this.missing = missing;
        this.repeated = repeated;
    }

    #endregion

    #region Actions - Headers

    /// Where the column is among `normalized`, a file's headers as `Normalized`
    /// spells them, or null when an optional column is absent. Throws
    /// `Rejected` with `InvalidCredentialFile` for a required column that is
    /// absent, or one named twice.
    public int? Index(IReadOnlyList<string> normalized) {
        ArgumentNullException.ThrowIfNull(normalized);
        var matches = Enumerable.Range(0, normalized.Count).Where(index => headers.Contains(normalized[index])).ToArray();
        if (matches.Length == 0)
            return missing is { } flaw ? throw new Rejected(new InvalidCredentialFile(flaw)) : null;
        if (matches.Length > 1 && repeated is { } ambiguous) throw new Rejected(new InvalidCredentialFile(ambiguous));
        return matches[0];
    }

    /// `header` as columns are compared: trimmed of spaces, line breaks and
    /// byte-order marks, in lowercase, with hyphens and spaces read as
    /// underscores.
    public static string Normalized(string header) {
        ArgumentNullException.ThrowIfNull(header);
        int start = 0, end = header.Length;
        while (start < end && IsTrimmed(header[start])) start++;
        while (end > start && IsTrimmed(header[end - 1])) end--;
        return header[start..end].ToLowerInvariant().Replace('-', '_').Replace(' ', '_');
    }

    private static bool IsTrimmed(char character) => char.IsWhiteSpace(character) || character == '\uFEFF';

    #endregion
}
