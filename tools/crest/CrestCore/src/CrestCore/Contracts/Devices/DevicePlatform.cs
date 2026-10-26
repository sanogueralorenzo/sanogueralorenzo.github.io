namespace CrestCore.Contracts;

/// The device class a rule answers for: desktop is the Mac, mobile is iPhone
/// and iPad. A platform carries every budget that differs by device, so a rule
/// asks the platform rather than naming one.
public sealed class DevicePlatform {
    #region Variables

    /// The Mac gives back one page under warning pressure and half of the
    /// eligible pages, at least one, under critical pressure. A page on screen
    /// is never taken. A manual setup left unfinished starts over at the next
    /// launch, setup asks which look its Spaces wear, and it imports from the
    /// browsers installed on it. First-run setup opens in a window of its own
    /// before any browser window. Agents the person runs on the Mac may use it.
    public static readonly DevicePlatform Desktop = new(name: "desktop", warningReleaseLimit: _ => 1,
        criticalReleaseLimit: eligible => Math.Max(1, (eligible + 1) / 2), keepsSetupDraft: false, choosesLook: true,
        importsBrowsers: true,
        sharesPagesAcrossWindows: true,
        forcesSetup: environment => environment.ForcesOnboardingWelcome || environment.ForcesDesktopSetup,
        setupHoldsFirstWindow: true, showcaseOpensStartPage: false, offersAgents: true);

    /// iPhone and iPad hold on under warning pressure and give back one page
    /// under critical pressure. Beyond that the system reclaims WebKit's page
    /// processes itself, as it does for Safari, and a reclaimed page comes
    /// back through crash recovery when it is shown. An unfinished manual setup
    /// waits for the next launch, since the system may end the app while it is
    /// in the background. First-run setup covers the browser, which opens
    /// beneath it as the person chose. No agent uses it.
    public static readonly DevicePlatform Mobile = new(name: "mobile", warningReleaseLimit: _ => 0,
        criticalReleaseLimit: _ => 1, keepsSetupDraft: true, choosesLook: false, importsBrowsers: false,
        sharesPagesAcrossWindows: false,
        forcesSetup: environment => environment.ForcesOnboardingWelcome || environment.ForcesMobileSetup,
        setupHoldsFirstWindow: false, showcaseOpensStartPage: true, offersAgents: false);

    public static IReadOnlyList<DevicePlatform> All { get; } = [Desktop, Mobile];

    public string Name { get; }

    /// Whether the device store keeps an unfinished manual setup for the next
    /// launch.
    public bool KeepsSetupDraft { get; }

    /// Whether setup asks which look the Spaces it makes wear, as the Mac's
    /// does on its way from the welcome. The core's own rule, which no
    /// platform reads.
    internal bool ChoosesLook { get; }

    /// Whether setup offers to import from other browsers installed here.
    /// Where it does not, setup goes from the welcome to setting up Spaces by
    /// hand.
    public bool ImportsBrowsers { get; }

    /// Whether the windows over one workspace share one set of pages, as the
    /// Mac's do; each iPad scene keeps pages of its own. The core's own rule,
    /// which no platform reads.
    internal bool SharesPagesAcrossWindows { get; }

    /// Whether first-run setup holds the launch's first browser window back
    /// until it finishes, as the Mac's does, so that window opens on the tab
    /// the person left rather than their startup choice. The core's own rule,
    /// which no platform reads.
    internal bool SetupHoldsFirstWindow { get; }

    /// Whether a launch that presents the showcase always opens on the Start
    /// Page, as the mobile showcase does, rather than where the launch would.
    /// The core's own rule, which no platform reads.
    internal bool ShowcaseOpensStartPage { get; }

    /// Whether agents the person runs on the device, such as coding agents,
    /// may use Crest. The core's own rule, which no platform reads.
    internal bool OffersAgents { get; }

    /// The most pages pressure at each level may take back, from the number of
    /// eligible pages.
    private readonly IReadOnlyDictionary<MemoryPressureLevel, Func<int, int>> releaseLimits;

    /// Whether a launch environment forces first-run setup on this platform,
    /// whatever the device completed.
    private readonly Func<LaunchEnvironment, bool> forcesSetup;

    #endregion

    #region Constructors

    private DevicePlatform(string name, Func<int, int> warningReleaseLimit, Func<int, int> criticalReleaseLimit,
        bool keepsSetupDraft, bool choosesLook, bool importsBrowsers, bool sharesPagesAcrossWindows,
        Func<LaunchEnvironment, bool> forcesSetup, bool setupHoldsFirstWindow, bool showcaseOpensStartPage, bool offersAgents) {
        Name = name;
        KeepsSetupDraft = keepsSetupDraft;
        ChoosesLook = choosesLook;
        ImportsBrowsers = importsBrowsers;
        SharesPagesAcrossWindows = sharesPagesAcrossWindows;
        SetupHoldsFirstWindow = setupHoldsFirstWindow;
        ShowcaseOpensStartPage = showcaseOpensStartPage;
        OffersAgents = offersAgents;
        this.forcesSetup = forcesSetup;
        releaseLimits = new Dictionary<MemoryPressureLevel, Func<int, int>> {
            [MemoryPressureLevel.Warning] = warningReleaseLimit,
            [MemoryPressureLevel.Critical] = criticalReleaseLimit
        };
    }

    #endregion

    #region Actions - Lookup

    public static DevicePlatform? Named(string? name) => All.FirstOrDefault(platform => platform.Name == name);

    #endregion

    #region Actions - Setup

    /// Whether `environment` forces first-run setup on this platform, whatever
    /// the device completed.
    internal bool ForcesSetup(LaunchEnvironment environment) {
        ArgumentNullException.ThrowIfNull(environment);
        return forcesSetup(environment);
    }

    #endregion

    #region Actions - Memory pressure

    /// How many of `eligiblePageCount` pages pressure at `level` may take back.
    public int ReleaseLimit(MemoryPressureLevel level, int eligiblePageCount) => releaseLimits[level](eligiblePageCount);

    #endregion
}
