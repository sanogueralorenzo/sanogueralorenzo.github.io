namespace CrestCore.Domain;

/// What a page does when its renderer stops: reload, or show the failure. A
/// renderer termination may be answered by reloading only so many times before
/// the page shows a failure instead of reloading forever.
public sealed class ProcessRecoveryAction {
    #region Static Variables

    public const int MaximumAutomaticReloads = 2;

    public static readonly ProcessRecoveryAction Reload = new(reloads: true);
    public static readonly ProcessRecoveryAction ShowFailure = new(reloads: false);

    public static IReadOnlyList<ProcessRecoveryAction> All { get; } = [Reload, ShowFailure];

    #endregion

    #region Variables

    /// The page reloads and its engine brings the renderer back.
    public bool Reloads { get; }

    #endregion

    #region Constructors

    private ProcessRecoveryAction(bool reloads) => Reloads = reloads;

    #endregion

    #region Actions - Lifecycle

    /// What a page does after `consecutiveTerminations` renderer terminations
    /// in a row.
    public static ProcessRecoveryAction For(int consecutiveTerminations) {
        ArgumentOutOfRangeException.ThrowIfLessThan(consecutiveTerminations, 1);
        return consecutiveTerminations <= MaximumAutomaticReloads ? Reload : ShowFailure;
    }

    #endregion
}
