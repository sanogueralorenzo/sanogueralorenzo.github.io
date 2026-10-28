namespace CrestCore.Contracts;

/// What iCloud says of the signed-in account, and what the settings call it.
///
/// A state travels as its index in `All`, so `All` is append-only.
public sealed class CloudAccountState {
    #region Variables

    public static readonly CloudAccountState Checking = new(name: "checking", title: "Checking");
    public static readonly CloudAccountState Available = new(name: "available", title: "Available");
    public static readonly CloudAccountState NoAccount = new(name: "noAccount", title: "Not signed in");
    public static readonly CloudAccountState Restricted = new(name: "restricted", title: "Restricted");
    public static readonly CloudAccountState TemporarilyUnavailable = new(name: "temporarilyUnavailable", title: "Temporarily unavailable");
    public static readonly CloudAccountState CouldNotDetermine = new(name: "couldNotDetermine", title: "Could not determine");

    public static IReadOnlyList<CloudAccountState> All { get; } =
        [Checking, Available, NoAccount, Restricted, TemporarilyUnavailable, CouldNotDetermine];

    public string Name { get; }

    /// What the settings call the account's state.
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private CloudAccountState(string name, string title) {
        Name = name;
        Title = title;
    }

    #endregion
}
