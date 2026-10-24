using CrestCore.Contracts;

namespace CrestCore.Application;

/// What each interruption an engine reports means for its download's record.
/// The engine contract fixes `EngineDownloadInterruption`'s spelling, so what
/// the core reads in one is declared here, and `Of` reads it.
internal sealed class EngineDownloadStop {
    #region Static Variables

    public static readonly EngineDownloadStop Network = new(EngineDownloadInterruption.Network, DownloadFailure.Network);
    public static readonly EngineDownloadStop Server = new(EngineDownloadInterruption.Server, DownloadFailure.Server);
    public static readonly EngineDownloadStop NoSpace = new(EngineDownloadInterruption.NoSpace, DownloadFailure.NoSpace);
    public static readonly EngineDownloadStop FileAccess = new(EngineDownloadInterruption.FileAccess, DownloadFailure.FileAccess);
    public static readonly EngineDownloadStop Other = new(EngineDownloadInterruption.Other, DownloadFailure.Interrupted);

    public static IReadOnlyList<EngineDownloadStop> All { get; } = [Network, Server, NoSpace, FileAccess, Other];

    #endregion

    #region Variables

    /// The interruption the engine reports.
    public EngineDownloadInterruption Interruption { get; }

    /// Why the download failed, in the words its row shows.
    public DownloadFailure Failure { get; }

    #endregion

    #region Constructors

    private EngineDownloadStop(EngineDownloadInterruption interruption, DownloadFailure failure) {
        Interruption = interruption;
        Failure = failure;
    }

    #endregion

    #region Actions - Lookup

    /// The stop the engine's `reported` interruption stands for.
    public static EngineDownloadStop Of(EngineDownloadInterruption reported) => All.First(stop => stop.Interruption == reported);

    #endregion
}
