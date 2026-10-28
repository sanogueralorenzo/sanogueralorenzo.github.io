namespace CrestCore.Contracts;

/// A capability a site asks for. `All` is the order the settings offer them in.
///
/// The saved permission document (`crest.site-permissions.v1`) and the
/// permission ledger's JSON spell a capability as its `Name`, so a name never
/// changes. Within one origin, saved choices are listed by name.
public sealed class SitePermission {
    #region Static Variables

    public static readonly SitePermission Camera = new(name: "camera", title: "Camera", symbol: "video",
        requestTitle: "Wants to use your camera", isMedia: true, isEngineEnforced: true);
    public static readonly SitePermission Microphone = new(name: "microphone", title: "Microphone", symbol: "mic",
        requestTitle: "Wants to use your microphone", isMedia: true, isEngineEnforced: true);
    public static readonly SitePermission CameraAndMicrophone = new(name: "cameraAndMicrophone", title: "Camera & Microphone",
        symbol: "video.and.waveform", requestTitle: "Wants to use your camera and microphone", isMedia: true,
        components: [Camera, Microphone]);
    public static readonly SitePermission Location = new(name: "location", title: "Location", symbol: "location",
        requestTitle: "Wants to use your location", isEngineEnforced: true);
    public static readonly SitePermission Notifications = new(name: "notifications", title: "Notifications", symbol: "bell",
        requestTitle: "Wants to send notifications", isEngineEnforced: true);
    // A site gets no automatic pop-ups until the person allows them.
    public static readonly SitePermission Popups = new(name: "popups", title: "Automatic Pop-ups", symbol: "macwindow.on.rectangle",
        requestTitle: "Requests permission", askTitle: "Blocked by Default", askChoiceTitle: "Default (Block)");
    // A site's first automatic download goes through; the next one asks.
    public static readonly SitePermission AutomaticDownloads = new(name: "automaticDownloads", title: "Automatic Downloads",
        symbol: "arrow.down.circle", requestTitle: "Wants to download multiple files automatically", askTitle: "Ask after First",
        askChoiceTitle: "Default (Ask after First)");
    public static readonly SitePermission ExternalApplications = new(name: "externalApplications", title: "External Apps",
        symbol: "arrow.up.forward.app", requestTitle: "Requests permission");
    // The system's sharing picker asks each time; a site can only be blocked.
    public static readonly SitePermission ScreenSharing = new(name: "screenSharing", title: "Screen Sharing",
        symbol: "rectangle.inset.filled.and.person.filled", requestTitle: "Wants to share your screen", isAskedBySystem: true);

    public static IReadOnlyList<SitePermission> All { get; } =
        [Camera, Microphone, CameraAndMicrophone, Location, Notifications, Popups, AutomaticDownloads, ExternalApplications,
            ScreenSharing];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the settings call the capability.
    [Localized]
    public string Title { get; }

    /// The SF Symbol shown beside the capability.
    public string Symbol { get; }

    /// What a site's request for the capability says it wants.
    [Localized]
    public string RequestTitle { get; }

    /// What the settings call the capability's Ask decision, which is what a
    /// site gets before the person answers.
    [Localized]
    public string AskTitle { get; }

    /// The settings' choice that returns the capability to Ask.
    [Localized]
    public string AskChoiceTitle { get; }

    /// A capture device, or several asked for together.
    public bool IsMedia { get; }

    /// An engine can enforce the capability itself. Crest's per-Space record
    /// decides it and the engine is told the answer.
    public bool IsEngineEnforced { get; }

    /// The system asks the person itself each time a site uses the
    /// capability, as its screen sharing picker does. Ask lets a request
    /// through to that question, and a site can be blocked but never allowed
    /// ahead of it.
    public bool IsAskedBySystem { get; }

    /// The capabilities a combined request asks for together, empty for one
    /// that stands alone. A decision for the combination answers for each of
    /// them, and a block on any of them blocks the combination.
    public IReadOnlyList<SitePermission> Components { get; }

    #endregion

    #region Constructors

    private SitePermission(string name, string title, string symbol, string requestTitle, bool isMedia = false,
        IReadOnlyList<SitePermission>? components = null, string askTitle = "Ask", string askChoiceTitle = "Ask",
        bool isEngineEnforced = false, bool isAskedBySystem = false) {
        Name = name;
        Title = title;
        Symbol = symbol;
        RequestTitle = requestTitle;
        AskTitle = askTitle;
        AskChoiceTitle = askChoiceTitle;
        IsMedia = isMedia;
        IsEngineEnforced = isEngineEnforced;
        IsAskedBySystem = isAskedBySystem;
        Components = components ?? [];
    }

    #endregion

    #region Actions - Lookup

    public static SitePermission? Named(string? name) => All.FirstOrDefault(permission => permission.Name == name);

    /// The capabilities that stand alone and that this one asks for: its
    /// components, or itself.
    public IReadOnlyList<SitePermission> Devices() => Components.Count > 0 ? Components : [this];

    /// The combined capabilities whose decisions also answer this one.
    public IReadOnlyList<SitePermission> Combinations() =>
        [.. All.Where(combination => combination.Components.Intersect(Devices()).Any())];

    #endregion
}
