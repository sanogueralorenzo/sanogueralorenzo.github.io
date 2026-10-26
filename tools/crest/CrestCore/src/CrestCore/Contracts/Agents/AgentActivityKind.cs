namespace CrestCore.Contracts;

/// What an agent did that changed the person's browser, as Settings › Agents
/// lists it under the agent. A kind travels as its index in `All`, so `All`
/// is append-only.
public sealed class AgentActivityKind {
    #region Variables

    public static readonly AgentActivityKind OpenedTab = new(name: "openedTab", title: "Opened a tab", symbol: "plus.square");
    public static readonly AgentActivityKind LoadedPage = new(name: "loadedPage", title: "Loaded a page",
        symbol: "arrow.right.circle");
    public static readonly AgentActivityKind ClosedTab = new(name: "closedTab", title: "Closed a tab", symbol: "xmark.square");
    public static readonly AgentActivityKind OpenedWindow = new(name: "openedWindow", title: "Opened a window",
        symbol: "macwindow.badge.plus");
    public static readonly AgentActivityKind OpenedPrivateWindow = new(name: "openedPrivateWindow",
        title: "Opened a private window", symbol: "eyeglasses");
    public static readonly AgentActivityKind DeletedHistory = new(name: "deletedHistory", title: "Deleted history",
        symbol: "clock.arrow.trianglehead.counterclockwise.rotate.90");
    public static readonly AgentActivityKind RanScript = new(name: "ranScript", title: "Ran a script", symbol: "curlybraces");

    public static IReadOnlyList<AgentActivityKind> All { get; } =
        [OpenedTab, LoadedPage, ClosedTab, OpenedWindow, OpenedPrivateWindow, DeletedHistory, RanScript];

    public string Name { get; }

    /// What Settings says the agent did.
    [Localized]
    public string Title { get; }

    /// The SF Symbol that stands for it.
    public string Symbol { get; }

    #endregion

    #region Constructors

    private AgentActivityKind(string name, string title, string symbol) {
        Name = name;
        Title = title;
        Symbol = symbol;
    }

    #endregion
}
