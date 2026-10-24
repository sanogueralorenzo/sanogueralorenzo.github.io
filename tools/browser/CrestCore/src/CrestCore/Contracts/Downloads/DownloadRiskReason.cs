namespace CrestCore.Contracts;

/// Why a download looks dangerous. Each reason decides from the platform's
/// facts whether it applies, and whether it holds even for a download the
/// person started.
///
/// An assessment lists its reasons in `All` order, and a reason travels as its
/// index there, so `All` is append-only.
public sealed class DownloadRiskReason {
    #region Variables

    public static readonly DownloadRiskReason ExecutableOrInstaller = new(name: "executableOrInstaller",
        applies: facts => facts.RunsCode, confirmsUserInitiated: false,
        message: "This file type can install or run software.");
    public static readonly DownloadRiskReason DeceptiveFilename = new(name: "deceptiveFilename",
        applies: facts => facts.HasDeceptiveFilename, confirmsUserInitiated: true,
        message: "The original filename used invisible or direction-changing characters that can disguise its real extension.");
    public static readonly DownloadRiskReason DangerousTypeMismatch = new(name: "dangerousTypeMismatch",
        applies: facts => facts.RunsCode && facts.TypesRelated == false, confirmsUserInitiated: true,
        message: "The server-reported file type does not match the filename and one of those types can run software.");

    public static IReadOnlyList<DownloadRiskReason> All { get; } = [ExecutableOrInstaller, DeceptiveFilename, DangerousTypeMismatch];

    private readonly Func<DownloadRiskFacts, bool> applies;

    public string Name { get; }

    /// Whether the person must confirm a download with this reason even when
    /// they started it. A user-initiated installer follows the platform's
    /// quarantine and Gatekeeper flow without an extra prompt; a disguised
    /// filename or a type mismatch that runs code stays suspicious however the
    /// download began.
    public bool ConfirmsUserInitiated { get; }

    /// Why the download looks dangerous, as the confirmation tells the person.
    [Localized]
    public string Message { get; }

    #endregion

    #region Constructors

    private DownloadRiskReason(string name, Func<DownloadRiskFacts, bool> applies, bool confirmsUserInitiated, string message) {
        Name = name;
        this.applies = applies;
        ConfirmsUserInitiated = confirmsUserInitiated;
        Message = message;
    }

    #endregion

    #region Actions - Risk

    public bool Applies(DownloadRiskFacts facts) {
        ArgumentNullException.ThrowIfNull(facts);
        return applies(facts);
    }

    public bool RequiresConfirmation(bool isUserInitiated) => !isUserInitiated || ConfirmsUserInitiated;

    #endregion

    #region Actions - Lookup

    public static DownloadRiskReason? Named(string? name) => All.FirstOrDefault(reason => reason.Name == name);

    #endregion
}
