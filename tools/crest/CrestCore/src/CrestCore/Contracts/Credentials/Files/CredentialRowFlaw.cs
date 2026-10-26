namespace CrestCore.Contracts;

/// Why one row of a password file is left out while the rest import, with
/// what the person is told. A flaw travels as its index in `All`, so `All` is
/// append-only.
public sealed class CredentialRowFlaw {
    #region Static Variables

    public static readonly CredentialRowFlaw InvalidOrigin = new(name: "invalidOrigin", message: "The site is not a valid web address.");
    public static readonly CredentialRowFlaw EmptyPassword = new(name: "emptyPassword", message: "The password is empty.");
    public static readonly CredentialRowFlaw MalformedRow = new(name: "malformedRow",
        message: "The row does not match the detected columns.");

    public static IReadOnlyList<CredentialRowFlaw> All { get; } = [InvalidOrigin, EmptyPassword, MalformedRow];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the person is told.
    [Localized]
    public string Message { get; }

    #endregion

    #region Constructors

    private CredentialRowFlaw(string name, string message) {
        Name = name;
        Message = message;
    }

    #endregion

    #region Actions - Lookup

    public static CredentialRowFlaw? Named(string? name) => All.FirstOrDefault(flaw => flaw.Name == name);

    #endregion
}
