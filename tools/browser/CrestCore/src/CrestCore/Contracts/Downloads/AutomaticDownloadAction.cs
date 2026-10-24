namespace CrestCore.Contracts;

/// What happens to a download a page started on its own. An action travels as
/// its index in `All`, so `All` is append-only.
public sealed class AutomaticDownloadAction {
    #region Types

    /// Each engine carries out an action with its own code, so the one place
    /// that carries it out switches over the kind.
    public enum Kinds { Allow, Deny, RequestPermission }

    #endregion

    #region Variables

    public static readonly AutomaticDownloadAction Allow = new(Kinds.Allow, name: "allow");
    public static readonly AutomaticDownloadAction Deny = new(Kinds.Deny, name: "deny");
    public static readonly AutomaticDownloadAction RequestPermission = new(Kinds.RequestPermission, name: "requestPermission");

    public static IReadOnlyList<AutomaticDownloadAction> All { get; } = [Allow, Deny, RequestPermission];

    public Kinds Kind { get; }
    public string Name { get; }

    #endregion

    #region Constructors

    private AutomaticDownloadAction(Kinds kind, string name) {
        Kind = kind;
        Name = name;
    }

    #endregion

    #region Actions - Lookup

    public static AutomaticDownloadAction? Named(string? name) => All.FirstOrDefault(action => action.Name == name);

    #endregion
}
