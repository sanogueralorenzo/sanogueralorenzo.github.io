namespace CrestCore.Contracts;

/// A feature an engine declares to the core when it registers, and to shared
/// UI. A capability travels as its index in `All`, so `All` is append-only.
public sealed class EngineCapability {
    #region Variables

    public static readonly EngineCapability Pages = new(name: "pages", isRequired: true);
    public static readonly EngineCapability Navigation = new(name: "navigation", isRequired: true);
    public static readonly EngineCapability Find = new(name: "find");
    public static readonly EngineCapability Zoom = new(name: "zoom");
    public static readonly EngineCapability InteractionState = new(name: "interaction-state");
    public static readonly EngineCapability PageResidency = new(name: "page-residency");
    public static readonly EngineCapability Popups = new(name: "popups");
    public static readonly EngineCapability WorkspaceProfiles = new(name: "workspace-profiles", isRequired: true);
    public static readonly EngineCapability WorkspaceTransfer = new(name: "workspace-transfer");
    public static readonly EngineCapability ProfileDeletion = new(name: "profile-deletion", isRequired: true);
    public static readonly EngineCapability ContentBlocking = new(name: "content-blocking");
    public static readonly EngineCapability Downloads = new(name: "downloads");
    public static readonly EngineCapability Permissions = new(name: "permissions");
    public static readonly EngineCapability Reader = new(name: "reader");
    public static readonly EngineCapability Translation = new(name: "translation");
    public static readonly EngineCapability SelectionTranslation = new(name: "selection-translation");
    public static readonly EngineCapability LocalFiles = new(name: "local-files");
    public static readonly EngineCapability Extensions = new(name: "extensions", startsEngineOnDemand: true);
    public static readonly EngineCapability ViewportCapture = new(name: "viewport-capture");
    public static readonly EngineCapability FullPageCapture = new(name: "full-page-capture");
    public static readonly EngineCapability Pdf = new(name: "pdf");
    public static readonly EngineCapability WebArchive = new(name: "web-archive");
    public static readonly EngineCapability Print = new(name: "print");
    public static readonly EngineCapability Inspector = new(name: "inspector");
    public static readonly EngineCapability FeatureFlags = new(name: "feature-flags");
    public static readonly EngineCapability BeforeUnload = new(name: "before-unload");
    public static readonly EngineCapability InternalPages = new(name: "internal-pages");
    /// The engine plays protected media through the platform's own content
    /// decryption, such as FairPlay on Apple platforms.
    public static readonly EngineCapability ProtectedMedia = new(name: "protected-media");
    /// The engine measures the sound a page plays, band by band, so its tab can
    /// show it.
    public static readonly EngineCapability AudioSpectrum = new(name: "audio-spectrum");

    public static IReadOnlyList<EngineCapability> All { get; } = [
        Pages, Navigation, Find, Zoom, InteractionState, PageResidency, Popups, WorkspaceProfiles, WorkspaceTransfer,
        ProfileDeletion, ContentBlocking, Downloads, Permissions, Reader, Translation, SelectionTranslation, LocalFiles,
        Extensions, ViewportCapture, FullPageCapture, Pdf, WebArchive, Print, Inspector, FeatureFlags, BeforeUnload,
        InternalPages, ProtectedMedia, AudioSpectrum
    ];

    /// The capabilities an engine must support to register.
    public static IReadOnlyList<EngineCapability> Required { get; } = [.. All.Where(capability => capability.IsRequired)];

    /// The capability's stored spelling, which platform settings name.
    public string Name { get; }

    /// Every browsing engine must support the capability to register. A Space
    /// is one profile, and deleting a Space must erase that profile, so an
    /// engine without profiles or their deletion cannot host a session at all.
    public bool IsRequired { get; }

    /// The device offers the capability while any registered engine supports
    /// it, even one no page is open on, because using it starts that engine.
    public bool StartsEngineOnDemand { get; }

    #endregion

    #region Constructors

    private EngineCapability(string name, bool isRequired = false, bool startsEngineOnDemand = false) {
        Name = name;
        IsRequired = isRequired;
        StartsEngineOnDemand = startsEngineOnDemand;
    }

    #endregion

    #region Actions - Lookup

    public static EngineCapability? Named(string? name) => All.FirstOrDefault(capability => capability.Name == name);

    #endregion
}
