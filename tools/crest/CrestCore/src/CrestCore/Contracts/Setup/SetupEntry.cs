namespace CrestCore.Contracts;

/// How the person arrived at setup: the step it opens on, whether it walks
/// them through Crest, whether it starts a manual setup over, and whether
/// finishing it opens the Getting Started guide. An entry travels as its index
/// in `All`, so `All` is append-only.
public sealed class SetupEntry {
    #region Static Variables

    /// The first launch on a device. Finishing opens the guide the first time.
    public static readonly SetupEntry FirstRun = new(name: "firstRun", firstStep: SetupStep.Welcome, isGuided: true,
        startsManualSetupOver: false, opensGuide: completed => !completed);
    /// Importing from another browser, asked for from the app.
    public static readonly SetupEntry ImportBrowser = new(name: "importBrowser", firstStep: SetupStep.ImportBrowser, isGuided: false,
        startsManualSetupOver: false, opensGuide: _ => false);
    /// Setting up Spaces by hand, asked for from the app.
    public static readonly SetupEntry ManualSetup = new(name: "manualSetup", firstStep: SetupStep.ManualSetup, isGuided: false,
        startsManualSetupOver: false, opensGuide: _ => false);
    /// Setup again from the start. Finishing always opens the guide.
    public static readonly SetupEntry Rerun = new(name: "rerun", firstStep: SetupStep.Welcome, isGuided: true,
        startsManualSetupOver: true, opensGuide: _ => true);

    public static IReadOnlyList<SetupEntry> All { get; } = [FirstRun, ImportBrowser, ManualSetup, Rerun];

    #endregion

    #region Variables

    public string Name { get; }

    /// The step setup opens on.
    public SetupStep FirstStep { get; }

    /// Whether setup walks the person through Crest from the welcome.
    public bool IsGuided { get; }

    /// Whether setup starts a manual setup over, where a device would
    /// otherwise go on with the one it kept.
    public bool StartsManualSetupOver { get; }

    private readonly Func<bool, bool> opensGuide;

    #endregion

    #region Constructors

    private SetupEntry(string name, SetupStep firstStep, bool isGuided, bool startsManualSetupOver, Func<bool, bool> opensGuide) {
        Name = name;
        FirstStep = firstStep;
        IsGuided = isGuided;
        StartsManualSetupOver = startsManualSetupOver;
        this.opensGuide = opensGuide;
    }

    #endregion

    #region Actions - Lookup

    public static SetupEntry? Named(string? name) => All.FirstOrDefault(entry => entry.Name == name);

    #endregion

    #region Actions - Finishing

    /// Whether finishing opens the Getting Started guide on a device that
    /// has, or has not, `completed` setup before.
    public bool OpensGuide(bool completed) => opensGuide(completed);

    #endregion
}
