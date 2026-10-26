namespace CrestCore.Contracts;

/// What the person should know about a row that imports, with what they are
/// told. A caution travels as its index in `All`, so `All` is append-only.
public sealed class CredentialRowCaution {
    #region Static Variables

    /// The row's site is plain HTTP: its password imports for manual use,
    /// and Crest never fills it over an insecure connection.
    public static readonly CredentialRowCaution InsecureOrigin = new(name: "insecureOrigin",
        message: "This HTTP site is not encrypted. Crest will import the password for manual access but will not autofill it on an insecure connection.");

    public static IReadOnlyList<CredentialRowCaution> All { get; } = [InsecureOrigin];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the person is told.
    [Localized]
    public string Message { get; }

    #endregion

    #region Constructors

    private CredentialRowCaution(string name, string message) {
        Name = name;
        Message = message;
    }

    #endregion

    #region Actions - Lookup

    public static CredentialRowCaution? Named(string? name) => All.FirstOrDefault(caution => caution.Name == name);

    #endregion
}
