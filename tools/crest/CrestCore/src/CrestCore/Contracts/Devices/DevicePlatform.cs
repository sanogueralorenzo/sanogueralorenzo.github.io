namespace CrestCore.Contracts;

/// The device class a rule answers for: desktop is the Mac, mobile is iPhone
/// and iPad. A platform carries every budget that differs by device, so a rule
/// asks the platform rather than naming one.
public sealed class DevicePlatform {
    #region Static Variables

    /// Mac page-reclamation budgets, shared pages, and local agent access.
    public static readonly DevicePlatform Desktop = new(name: "desktop", warningReleaseLimit: _ => 1,
        criticalReleaseLimit: eligible => Math.Max(1, (eligible + 1) / 2), sharesPagesAcrossWindows: true,
        offersAgents: true);

    /// Mobile page-reclamation budgets and independent windows.
    public static readonly DevicePlatform Mobile = new(name: "mobile", warningReleaseLimit: _ => 0,
        criticalReleaseLimit: _ => 1, sharesPagesAcrossWindows: false,
        offersAgents: false);

    public static IReadOnlyList<DevicePlatform> All { get; } = [Desktop, Mobile];

    #endregion

    #region Variables

    public string Name { get; }

    /// Whether the windows over one workspace share one set of pages, as the
    /// Mac's do; each iPad scene keeps pages of its own. The core's own rule,
    /// which no platform reads.
    internal bool SharesPagesAcrossWindows { get; }

    /// Whether agents the person runs on the device, such as coding agents,
    /// may use Crest. The core's own rule, which no platform reads.
    internal bool OffersAgents { get; }

    /// The most pages pressure at each level may take back, from the number of
    /// eligible pages.
    private readonly IReadOnlyDictionary<MemoryPressureLevel, Func<int, int>> releaseLimits;

    #endregion

    #region Constructors

    private DevicePlatform(string name, Func<int, int> warningReleaseLimit, Func<int, int> criticalReleaseLimit,
        bool sharesPagesAcrossWindows,
        bool offersAgents) {
        Name = name;
        SharesPagesAcrossWindows = sharesPagesAcrossWindows;
        OffersAgents = offersAgents;
        releaseLimits = new Dictionary<MemoryPressureLevel, Func<int, int>> {
            [MemoryPressureLevel.Warning] = warningReleaseLimit,
            [MemoryPressureLevel.Critical] = criticalReleaseLimit
        };
    }

    #endregion

    #region Actions - Lookup

    public static DevicePlatform? Named(string? name) => All.FirstOrDefault(platform => platform.Name == name);

    #endregion

    #region Actions - Memory pressure

    /// How many of `eligiblePageCount` pages pressure at `level` may take back.
    public int ReleaseLimit(MemoryPressureLevel level, int eligiblePageCount) => releaseLimits[level](eligiblePageCount);

    #endregion
}
