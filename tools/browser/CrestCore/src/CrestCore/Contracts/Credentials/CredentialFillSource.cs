namespace CrestCore.Contracts;

/// What the person asked to fill, and the password field it fills. A source
/// travels as its index in `All`, so `All` is append-only.
public sealed class CredentialFillSource {
    #region Static Variables

    /// A saved credential, which fills a field asking for the current password.
    public static readonly CredentialFillSource Saved = new(name: "saved", fills: CredentialPasswordKind.Current);
    /// A generated password, which fills only a field asking for a new one.
    public static readonly CredentialFillSource Generated = new(name: "generated", fills: CredentialPasswordKind.New);

    public static IReadOnlyList<CredentialFillSource> All { get; } = [Saved, Generated];

    #endregion

    #region Variables

    public string Name { get; }

    /// The kind of password field the source fills; it is offered to no other.
    public CredentialPasswordKind Fills { get; }

    #endregion

    #region Constructors

    private CredentialFillSource(string name, CredentialPasswordKind fills) {
        Name = name;
        Fills = fills;
    }

    #endregion

    #region Actions - Lookup

    public static CredentialFillSource? Named(string? name) => All.FirstOrDefault(source => source.Name == name);

    #endregion

    #region Actions - Filling

    /// Saved credentials are offered to current-password fields; generated
    /// passwords only to new-password fields.
    internal bool Offers(CredentialPasswordKind passwordKind) => Fills == passwordKind;

    #endregion
}
