namespace CrestCore.Contracts;

/// What importing one candidate password does to the Space's saved
/// passwords. An effect travels as its index in `All`, so `All` is
/// append-only.
public sealed class CredentialImportEffect {
    #region Static Variables

    /// No password is saved for the account: the candidate is added.
    public static readonly CredentialImportEffect Adds = new(name: "adds", changesPasswords: true);
    /// The account's saved password differs: the candidate replaces it.
    public static readonly CredentialImportEffect Replaces = new(name: "replaces", changesPasswords: true);
    /// The account's saved password is the candidate: nothing changes.
    public static readonly CredentialImportEffect Matches = new(name: "matches", changesPasswords: false);

    public static IReadOnlyList<CredentialImportEffect> All { get; } = [Adds, Replaces, Matches];

    #endregion

    #region Variables

    public string Name { get; }

    /// Whether importing the candidate changes the saved passwords, which an
    /// import counts as accepted.
    public bool ChangesPasswords { get; }

    #endregion

    #region Constructors

    private CredentialImportEffect(string name, bool changesPasswords) {
        Name = name;
        ChangesPasswords = changesPasswords;
    }

    #endregion

    #region Actions - Lookup

    public static CredentialImportEffect? Named(string? name) => All.FirstOrDefault(effect => effect.Name == name);

    #endregion
}
