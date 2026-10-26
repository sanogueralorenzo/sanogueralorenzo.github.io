namespace CrestCore.Contracts;

/// Why a page's navigation failed, as either engine reports it, and how the
/// failure page presents it. `Code` is the stable spelling the failure page
/// shows, so a report names the same problem whichever engine saw it. An
/// error travels as its index in `All`, so `All` is append-only.
public sealed class NavigationError {
    #region Static Variables

    /// Suggestions several errors share.
    private const string ConnectedVpn = "If you use a VPN or proxy, confirm that it is connected.";
    private const string RetryConnection = "Check your connection and try again in a moment.";
    private const string CheckAddress = "Check the address for typing mistakes.";
    private const string CheckElsewhere = "Check whether the site is available in another browser or device.";
    private const string RequiredNetwork = "For an intranet site, confirm that you are on the required network.";

    public static readonly NavigationError Offline = new(name: "offline", code: "CREST_INTERNET_DISCONNECTED", title: "You’re offline",
        message: "Crest can’t reach %@ without a network connection.",
        primarySuggestion: "Reconnect to Wi-Fi or Ethernet, then try again.", secondarySuggestion: ConnectedVpn, symbol: "wifi.slash");
    public static readonly NavigationError TimedOut = new(name: "timedOut", code: "CREST_TIMED_OUT",
        title: "This site took too long to respond", message: "%@ didn’t respond in time.", primarySuggestion: RetryConnection,
        secondarySuggestion: ConnectedVpn, symbol: "clock.badge.exclamationmark");
    public static readonly NavigationError CannotFindServer = new(name: "cannotFindServer", code: "CREST_NAME_NOT_RESOLVED",
        title: "Server not found", message: "Crest couldn’t find the server for %@.", primarySuggestion: CheckAddress,
        secondarySuggestion: "If the address is correct, check your DNS or VPN settings.", symbol: "network.slash");
    public static readonly NavigationError CannotConnect = new(name: "cannotConnect", code: "CREST_CONNECTION_REFUSED",
        title: "This site can’t be reached", message: "%@ refused the connection or isn’t accepting connections.",
        primarySuggestion: CheckElsewhere, secondarySuggestion: RequiredNetwork, symbol: "exclamationmark.icloud");
    public static readonly NavigationError ConnectionLost = new(name: "connectionLost", code: "CREST_CONNECTION_RESET",
        title: "The connection was interrupted", message: "The connection to %@ ended before the page finished loading.",
        primarySuggestion: RetryConnection, secondarySuggestion: ConnectedVpn, symbol: "bolt.horizontal.icloud");
    public static readonly NavigationError SecureConnectionFailed = new(name: "secureConnectionFailed", code: "CREST_CERTIFICATE_INVALID",
        title: "A secure connection couldn’t be made", message: "Crest couldn’t verify a private, secure connection to %@.",
        primarySuggestion: "Check that your device’s date and time are correct.",
        secondarySuggestion: "Avoid entering private information until the site fixes its certificate.",
        symbol: "lock.trianglebadge.exclamationmark");
    public static readonly NavigationError TooManyRedirects = new(name: "tooManyRedirects", code: "CREST_TOO_MANY_REDIRECTS",
        title: "This page is redirecting incorrectly", message: "%@ sent Crest through too many redirects.",
        primarySuggestion: "Try again later; the site may be temporarily misconfigured.",
        secondarySuggestion: "Opening the site’s home page may avoid the redirect loop.",
        symbol: "arrow.trianglehead.2.clockwise.rotate.90");
    public static readonly NavigationError UnsupportedAddress = new(name: "unsupportedAddress", code: "CREST_UNSUPPORTED_ADDRESS",
        title: "Crest can’t open this address", message: "The address uses a format or protocol Crest doesn’t support.",
        primarySuggestion: CheckAddress, secondarySuggestion: "Try an address beginning with http:// or https://.",
        symbol: "link.badge.plus");
    public static readonly NavigationError Blocked = new(name: "blocked", code: "CREST_CONTENT_BLOCKED", title: "This page was blocked",
        message: "A security or content policy prevented this page from loading.",
        primarySuggestion: "Review this Space’s content and network settings.",
        secondarySuggestion: "A firewall, filter, or device policy may also be responsible.", symbol: "hand.raised.slash");
    public static readonly NavigationError Unavailable = new(name: "unavailable", code: "CREST_RESOURCE_UNAVAILABLE",
        title: "This page isn’t available", message: "%@ returned a response Crest couldn’t load.", primarySuggestion: CheckElsewhere,
        secondarySuggestion: RequiredNetwork, symbol: "exclamationmark.icloud");
    public static readonly NavigationError WebContentProcessStopped = new(name: "webContentProcessStopped",
        code: "CREST_WEB_PROCESS_STOPPED", title: "This page stopped responding",
        message: "The web content process stopped repeatedly. Your tab and address are safe.",
        primarySuggestion: "Try reloading the page in a fresh web content process.",
        secondarySuggestion: "If it happens again, try closing and reopening the tab.",
        symbol: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90");
    public static readonly NavigationError Unknown = new(name: "unknown", code: "CREST_NAVIGATION_FAILED",
        title: "This page couldn’t be opened", message: "Crest encountered an unexpected problem while opening %@.",
        primarySuggestion: "Try the address again or open a different page.",
        secondarySuggestion: "The technical details below can help identify the cause.", symbol: "doc.badge.ellipsis");

    public static IReadOnlyList<NavigationError> All { get; } = [
        Offline, TimedOut, CannotFindServer, CannotConnect, ConnectionLost, SecureConnectionFailed, TooManyRedirects,
        UnsupportedAddress, Blocked, Unavailable, WebContentProcessStopped, Unknown
    ];

    #endregion

    #region Variables

    public string Name { get; }

    /// The error code the failure page shows and a support request quotes.
    public string Code { get; }

    /// The failure page's headline.
    [Localized]
    public string Title { get; }

    /// What went wrong, as the failure page explains it. A message that names
    /// the site spells `%@` where the platform puts the page's host.
    [Localized]
    public string Message { get; }

    /// What the failure page suggests trying first, and next.
    [Localized]
    public string PrimarySuggestion { get; }

    [Localized]
    public string SecondarySuggestion { get; }

    /// The SF Symbol the failure page shows.
    public string Symbol { get; }

    #endregion

    #region Constructors

    private NavigationError(string name, string code, string title, string message, string primarySuggestion,
        string secondarySuggestion, string symbol) {
        Name = name;
        Code = code;
        Title = title;
        Message = message;
        PrimarySuggestion = primarySuggestion;
        SecondarySuggestion = secondarySuggestion;
        Symbol = symbol;
    }

    #endregion

    #region Actions - Lookup

    public static NavigationError? Named(string? name) => All.FirstOrDefault(error => error.Name == name);

    #endregion
}
