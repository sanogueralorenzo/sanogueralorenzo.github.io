namespace CrestCore.Contracts;

/// What happened to a page's blocked-popup indication, described by the status
/// it applies from and the status it leaves.
///
/// The page's content bridge coalesces before crossing into native code, and
/// these transitions are the second boundary: even a hostile page posting
/// directly to the bridge cannot stack indications or announcements in one
/// document. An event travels as its index in `All`, so `All` is append-only.
public sealed class BlockedPopupEvent {
    #region Variables

    /// The engine or the page's bridge held back an automatic popup. It needs
    /// the document identifier and the blocked site's origin, and shows one
    /// new indication unless one is already shown.
    public static readonly BlockedPopupEvent Blocked = new(name: "blocked", from: null, to: BlockedPopupStatus.Blocked,
        startsIndication: true);

    /// The person allowed automatic popups for the blocked site.
    public static readonly BlockedPopupEvent PermissionAllowed = new(name: "permission_allowed", from: BlockedPopupStatus.Blocked,
        to: BlockedPopupStatus.AllowedAwaitingRetry);

    /// Automatic popups were blocked again before the page retried.
    public static readonly BlockedPopupEvent PermissionBlockedAgain = new(name: "permission_blocked_again",
        from: BlockedPopupStatus.AllowedAwaitingRetry, to: BlockedPopupStatus.Blocked);

    /// The page started a new navigation, which clears whatever it showed.
    public static readonly BlockedPopupEvent Navigation = new(name: "navigation", from: null, to: null, fromAnything: true);

    /// A popup opened after the person allowed it.
    public static readonly BlockedPopupEvent PopupAllowed = new(name: "popup_allowed", from: BlockedPopupStatus.AllowedAwaitingRetry,
        to: null);

    public static IReadOnlyList<BlockedPopupEvent> All { get; } =
        [Blocked, PermissionAllowed, PermissionBlockedAgain, Navigation, PopupAllowed];

    public string Name { get; }

    /// The status the page must show for the event to change anything, or
    /// null when it must show none.
    public BlockedPopupStatus? From { get; }

    /// The event changes any page that shows an indication or holds a
    /// document, whatever its status.
    public bool FromAnything { get; }

    /// The status the page shows afterwards, or null when the indication clears.
    public BlockedPopupStatus? To { get; }

    /// The event starts a new indication for a document and an origin, which
    /// the page announces once.
    public bool StartsIndication { get; }

    #endregion

    #region Constructors

    private BlockedPopupEvent(string name, BlockedPopupStatus? from, BlockedPopupStatus? to, bool fromAnything = false,
        bool startsIndication = false) {
        Name = name;
        From = from;
        FromAnything = fromAnything;
        To = to;
        StartsIndication = startsIndication;
    }

    #endregion

    #region Actions - Lookup

    public static BlockedPopupEvent? Named(string? name) => All.FirstOrDefault(popupEvent => popupEvent.Name == name);

    #endregion
}
