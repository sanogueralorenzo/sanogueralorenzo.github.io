namespace CrestCore.Contracts;

/// What a download's row offers the person. Each phase names its action, and
/// each action carries its label and symbol. Opening a finished file offers the
/// platform's destinations, labeled by the platform; the action's own label and
/// symbol name the menu that holds them.
public sealed class DownloadRowAction {
    #region Types

    /// Each platform performs an action with its own code, so the one place
    /// that performs it switches over the kind.
    public enum Kinds { Retry, Cancel, Open, Remove, Pause, Resume }

    #endregion

    #region Variables

    public static readonly DownloadRowAction Retry = new(Kinds.Retry, name: "retry", title: "Allow Download", symbol: "arrow.clockwise");
    public static readonly DownloadRowAction Cancel = new(Kinds.Cancel, name: "cancel", title: "Cancel Download", symbol: "xmark");
    public static readonly DownloadRowAction Open = new(Kinds.Open, name: "open", title: "Download Actions", symbol: "square.and.arrow.up");
    public static readonly DownloadRowAction Remove = new(Kinds.Remove, name: "remove", title: "Remove Download", symbol: "trash",
        isDestructive: true);

    public static readonly DownloadRowAction Pause = new(Kinds.Pause, name: "pause", title: "Pause Download", symbol: "pause");
    public static readonly DownloadRowAction Resume = new(Kinds.Resume, name: "resume", title: "Resume Download", symbol: "play");

    public static IReadOnlyList<DownloadRowAction> All { get; } = [Retry, Cancel, Open, Remove, Pause, Resume];

    public Kinds Kind { get; }
    public string Name { get; }

    [Localized]
    public string Title { get; }

    /// The SF Symbol for the action's button.
    public string Symbol { get; }

    /// The action discards something, so its button says so.
    public bool IsDestructive { get; }

    #endregion

    #region Constructors

    private DownloadRowAction(Kinds kind, string name, string title, string symbol, bool isDestructive = false) {
        Kind = kind;
        Name = name;
        Title = title;
        Symbol = symbol;
        IsDestructive = isDestructive;
    }

    #endregion

    #region Actions - Lookup

    public static DownloadRowAction? Named(string? name) => All.FirstOrDefault(action => action.Name == name);

    #endregion
}
