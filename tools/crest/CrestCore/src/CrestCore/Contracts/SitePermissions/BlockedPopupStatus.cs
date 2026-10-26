namespace CrestCore.Contracts;

/// The one blocked-popup indication a document may show. A status travels as
/// its index in `All`, so `All` is append-only.
public sealed class BlockedPopupStatus {
    #region Variables

    public static readonly BlockedPopupStatus Blocked = new(name: "blocked", symbol: "macwindow.badge.plus", offersAllow: true,
        guidance: "Automatic pop-ups are blocked. Allow them for this site, then retry the action on the page.");
    public static readonly BlockedPopupStatus AllowedAwaitingRetry = new(name: "allowedAwaitingRetry", symbol: "checkmark.circle",
        offersAllow: false, guidance: "Retry the action on the page. Crest did not reopen the blocked pop-up.");

    public static IReadOnlyList<BlockedPopupStatus> All { get; } = [Blocked, AllowedAwaitingRetry];

    public string Name { get; }

    /// The SF Symbol the site control shows for the indication.
    public string Symbol { get; }

    /// What the site control tells the person to do.
    [Localized]
    public string Guidance { get; }

    /// The indication offers to allow automatic pop-ups for the site.
    public bool OffersAllow { get; }

    #endregion

    #region Constructors

    private BlockedPopupStatus(string name, string symbol, bool offersAllow, string guidance) {
        Name = name;
        Symbol = symbol;
        OffersAllow = offersAllow;
        Guidance = guidance;
    }

    #endregion

    #region Actions - Lookup

    public static BlockedPopupStatus? Named(string? name) => All.FirstOrDefault(status => status.Name == name);

    #endregion
}
