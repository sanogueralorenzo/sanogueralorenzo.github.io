namespace CrestCore.Contracts;

/// How the signed-in iCloud account changed.
///
/// A choice travels as its index in `All`, so `All` is append-only.
public sealed class CloudAccountTransition {
    #region Variables

    /// An account signed in where none was: the first sign-in is not a
    /// conflict with anything.
    public static readonly CloudAccountTransition SignIn = new(name: "signIn", alwaysPauses: false);
    public static readonly CloudAccountTransition SignOut = new(name: "signOut", alwaysPauses: true);
    public static readonly CloudAccountTransition SwitchAccounts = new(name: "switchAccounts", alwaysPauses: true);
    /// A change the transport cannot name, which pauses as a switch does.
    public static readonly CloudAccountTransition Unknown = new(name: "unknown", alwaysPauses: true);

    public static IReadOnlyList<CloudAccountTransition> All { get; } = [SignIn, SignOut, SwitchAccounts, Unknown];

    public string Name { get; }

    /// Whether the change pauses sync until the person decides which copy to
    /// keep, whatever came before it.
    public bool AlwaysPauses { get; }

    #endregion

    #region Constructors

    private CloudAccountTransition(string name, bool alwaysPauses) {
        Name = name;
        AlwaysPauses = alwaysPauses;
    }

    #endregion
}
