using CrestCore.Domain;

namespace CrestCore.Contracts;

/// Why a password file cannot be imported at all, with what the person is
/// told. A flaw travels as its index in `All`, so `All` is append-only.
public sealed class CredentialFileFlaw {
    #region Static Variables

    public static readonly CredentialFileFlaw TooLarge = new(name: "tooLarge",
        message: "This password file is larger than Crest’s 16 MB import limit.");
    public static readonly CredentialFileFlaw NotText = new(name: "notText", message: "This password file is not valid UTF-8 text.");
    public static readonly CredentialFileFlaw Empty = new(name: "empty", message: "This password file is empty.");
    public static readonly CredentialFileFlaw NoRows = new(name: "noRows",
        message: "This password file contains supported headers but no credential rows.");
    public static readonly CredentialFileFlaw Malformed = new(name: "malformed",
        message: "This password file contains malformed CSV quoting or columns.", answers: CsvFault.Malformed);
    public static readonly CredentialFileFlaw TooManyRows = new(name: "tooManyRows",
        message: "This password file contains more than 10,000 credential rows.", answers: CsvFault.TooManyRows);
    public static readonly CredentialFileFlaw TooManyColumns = new(name: "tooManyColumns",
        message: "This password file contains too many columns.", answers: CsvFault.TooManyColumns);
    public static readonly CredentialFileFlaw FieldTooLarge = new(name: "fieldTooLarge",
        message: "A field in this password file is too large to import safely.", answers: CsvFault.FieldTooLarge);
    public static readonly CredentialFileFlaw NoSiteColumn = new(name: "noSiteColumn",
        message: "This password file has no supported site column.");
    public static readonly CredentialFileFlaw NoUsernameColumn = new(name: "noUsernameColumn",
        message: "This password file has no supported username column.");
    public static readonly CredentialFileFlaw NoPasswordColumn = new(name: "noPasswordColumn",
        message: "This password file has no supported password column.");
    public static readonly CredentialFileFlaw SeveralSiteColumns = new(name: "severalSiteColumns",
        message: "This password file has more than one possible site column. Remove the ambiguity and try again.");
    public static readonly CredentialFileFlaw SeveralUsernameColumns = new(name: "severalUsernameColumns",
        message: "This password file has more than one possible username column. Remove the ambiguity and try again.");
    public static readonly CredentialFileFlaw SeveralPasswordColumns = new(name: "severalPasswordColumns",
        message: "This password file has more than one possible password column. Remove the ambiguity and try again.");

    public static IReadOnlyList<CredentialFileFlaw> All { get; } = [TooLarge, NotText, Empty, NoRows, Malformed, TooManyRows,
        TooManyColumns, FieldTooLarge, NoSiteColumn, NoUsernameColumn, NoPasswordColumn, SeveralSiteColumns, SeveralUsernameColumns,
        SeveralPasswordColumns];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the person is told.
    [Localized]
    public string Message { get; }

    /// The way a file's text breaks CSV that the flaw stands for, or null for
    /// a flaw of what the CSV holds. The core's own reading, which no
    /// platform reads.
    internal CsvFault? Answers { get; }

    #endregion

    #region Constructors

    private CredentialFileFlaw(string name, string message, CsvFault? answers = null) {
        Name = name;
        Message = message;
        Answers = answers;
    }

    #endregion

    #region Actions - Lookup

    public static CredentialFileFlaw? Named(string? name) => All.FirstOrDefault(flaw => flaw.Name == name);

    /// The flaw a file's text breaking CSV with `fault` means.
    internal static CredentialFileFlaw Answering(CsvFault fault) => All.First(flaw => flaw.Answers == fault);

    #endregion
}
