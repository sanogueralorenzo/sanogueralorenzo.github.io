namespace CrestCore.Contracts;

/// Whether websites in Crest can use the system's passkey providers, and what
/// the settings say about it.
///
/// `Checking` is what the settings show until the platform has asked; the
/// core never answers it. A status travels as its index in `All`, so `All` is
/// append-only.
public sealed class PasskeyAccessStatus {
    #region Variables

    public static readonly PasskeyAccessStatus ManagedCapabilityRequired = new(name: "managedCapabilityRequired",
        title: "Awaiting Apple approval",
        detail: "This build cannot request browser-wide passkey access until Apple approves Crest’s managed capability.",
        symbol: "checkmark.seal",
        settingsDetail: "This build of Crest does not include permission to request browser passkey access.");
    public static readonly PasskeyAccessStatus DeviceNotConfigured = new(name: "deviceNotConfigured",
        title: "Passkeys aren’t configured", detail: "Configure passkeys in system settings, then reopen Crest.", symbol: "key.slash",
        settingsDetail: "Finish setting up passkeys in System Settings, then check again.", needsAttention: true);
    public static readonly PasskeyAccessStatus NotDetermined = new(name: "notDetermined", title: "Permission required",
        detail: "Allow Crest to use the system’s passkey providers for the website in the active page.", symbol: "person.badge.key",
        canRequestAccess: true);
    public static readonly PasskeyAccessStatus Authorized = new(name: "authorized", title: "Ready for websites",
        detail: "WebKit can use the system’s passkey providers for the website in the active page.", symbol: "person.badge.key.fill",
        isReady: true);
    public static readonly PasskeyAccessStatus Denied = new(name: "denied", title: "Passkey access is off",
        detail: "Turn on Crest under Privacy & Security > Passkeys Access for Web Browsers in system settings.",
        symbol: "hand.raised.slash",
        settingsDetail: "Turn on Crest under Privacy & Security > Passkeys Access for Web Browsers in system settings.",
        needsAttention: true);
    public static readonly PasskeyAccessStatus Checking = new(name: "checking", title: "Checking passkey access",
        detail: "Crest is checking this build and the system’s browser-passkey setting.", symbol: "ellipsis.circle",
        isChecking: true);

    public static IReadOnlyList<PasskeyAccessStatus> All { get; } =
        [ManagedCapabilityRequired, DeviceNotConfigured, NotDetermined, Authorized, Denied, Checking];

    public string Name { get; }

    [Localized]
    public string Title { get; }

    [Localized]
    public string Detail { get; }

    /// The SF Symbol shown beside the status.
    public string Symbol { get; }

    /// What the system permissions list says under the status, when it says
    /// more than the status itself.
    [Localized]
    public string? SettingsDetail { get; }

    /// Websites can use the system's passkey providers.
    public bool IsReady { get; }

    /// The person must change something in system settings.
    public bool NeedsAttention { get; }

    /// Only an explicit request from the person may ask the system for consent.
    public bool CanRequestAccess { get; }

    /// No answer has arrived yet.
    public bool IsChecking { get; }

    #endregion

    #region Constructors

    private PasskeyAccessStatus(string name, string title, string detail, string symbol, string? settingsDetail = null,
        bool isReady = false, bool needsAttention = false, bool canRequestAccess = false, bool isChecking = false) {
        Name = name;
        Title = title;
        Detail = detail;
        Symbol = symbol;
        SettingsDetail = settingsDetail;
        IsReady = isReady;
        NeedsAttention = needsAttention;
        CanRequestAccess = canRequestAccess;
        IsChecking = isChecking;
    }

    #endregion

    #region Actions - Lookup

    public static PasskeyAccessStatus? Named(string? name) => All.FirstOrDefault(status => status.Name == name);

    #endregion
}
