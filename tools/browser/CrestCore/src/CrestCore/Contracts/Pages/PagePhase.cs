namespace CrestCore.Contracts;

/// Where a page stands on its engine. A page opens, and its engine then
/// creates it or fails to; a page that is live or still opening can close on
/// its own. A phase only follows the phases it names, so a late or repeated
/// report changes nothing. A phase travels as its index in `All`, so `All` is
/// append-only.
public sealed class PagePhase {
    #region Variables

    public static readonly PagePhase Opening = new(name: "opening", holdsEnginePage: true, follows: _ => false);
    public static readonly PagePhase Live = new(name: "live", holdsEnginePage: true, follows: phase => phase == Opening);
    public static readonly PagePhase Failed = new(name: "failed", holdsEnginePage: false, follows: phase => phase == Opening);
    public static readonly PagePhase Closed = new(name: "closed", holdsEnginePage: false, follows: phase => phase.HoldsEnginePage);

    public static IReadOnlyList<PagePhase> All { get; } = [Opening, Live, Failed, Closed];

    public string Name { get; }

    /// The engine holds a page, or is making one, that closing the page must
    /// close too.
    public bool HoldsEnginePage { get; }

    /// Which phases a page may leave for this one.
    private readonly Func<PagePhase, bool> follows;

    #endregion

    #region Constructors

    private PagePhase(string name, bool holdsEnginePage, Func<PagePhase, bool> follows) {
        Name = name;
        HoldsEnginePage = holdsEnginePage;
        this.follows = follows;
    }

    #endregion

    #region Actions - Lookup

    public static PagePhase? Named(string? name) => All.FirstOrDefault(phase => phase.Name == name);

    #endregion

    #region Actions - Transitions

    /// Whether a page in `phase` may move to this one.
    public bool Follows(PagePhase phase) => follows(phase);

    #endregion
}
