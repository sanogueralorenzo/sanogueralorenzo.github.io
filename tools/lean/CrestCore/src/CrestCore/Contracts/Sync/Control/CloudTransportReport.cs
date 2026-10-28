using CrestCore.Application;

namespace CrestCore.Contracts;

/// What a running transport reported of itself.
///
/// A report travels as its index in `All`, so `All` is append-only.
public sealed class CloudTransportReport {
    #region Static Variables

    public static readonly CloudTransportReport Stopped = new(name: "stopped", settle: Status((control, _) =>
        control.Phase = control.IsEnabled ? CloudSyncPhase.Checking : CloudSyncPhase.Disabled));
    public static readonly CloudTransportReport Syncing = new(name: "syncing", settle: Status((control, _) =>
        control.Phase = CloudSyncPhase.Syncing));
    public static readonly CloudTransportReport Idle = new(name: "idle", settle: Status((control, _) => {
        control.Phase = CloudSyncPhase.Ready;
        return control.ClearRecoveredFailure();
    }));
    public static readonly CloudTransportReport PausedForAccountConfirmation = new(name: "pausedForAccountConfirmation",
        settle: Status((control, _) => control.Phase = CloudSyncPhase.NeedsReconciliation));
    /// The transport failed; the report carries its words.
    public static readonly CloudTransportReport Failed = new(name: "failed", settle: Status((control, reported) =>
        control.Fail(reported.Message ?? string.Empty)));
    /// A batch of records arrived; the report counts the ones applied.
    public static readonly CloudTransportReport Fetched = new(name: "fetched", settle: (control, reported) => {
        control.LastFetched = reported.RecordCount;
        return Succeeded(control);
    });
    /// A batch of records uploaded; the report counts them.
    public static readonly CloudTransportReport Uploaded = new(name: "uploaded", settle: (control, reported) => {
        control.LastUploaded = reported.RecordCount;
        return Succeeded(control);
    });
    /// The account changed under the running transport.
    public static readonly CloudTransportReport AccountChanged = new(name: "accountChanged", settle: (control, _) => RestartForAccount(control));
    /// Records arrived that this build could not read; the report counts
    /// them, and whether a newer build wrote some.
    public static readonly CloudTransportReport SkippedRecords = new(name: "skippedRecords", settle: (control, reported) => {
        control.Skipped += reported.RecordCount;
        control.RequiresAppUpdate |= reported.RequiresAppUpdate;
        return [];
    });
    /// Somebody removed Crest's data from iCloud.
    public static readonly CloudTransportReport CloudDataRemoved = new(name: "cloudDataRemoved", settle: (control, _) => {
        control.CloudDataRemoved = true;
        return [];
    });

    public static IReadOnlyList<CloudTransportReport> All { get; } =
        [Stopped, Syncing, Idle, PausedForAccountConfirmation, Failed, Fetched, Uploaded, AccountChanged, SkippedRecords, CloudDataRemoved];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the report does to the sync control, and the steps that follow.
    private readonly Func<CloudSyncControl, CloudTransportReported, List<CloudSyncStep>> settle;

    #endregion

    #region Constructors

    private CloudTransportReport(string name, Func<CloudSyncControl, CloudTransportReported, List<CloudSyncStep>> settle) {
        Name = name;
        this.settle = settle;
    }

    #endregion

    #region Actions - Sync

    /// What `reported`, a report of this kind, does to `control`.
    internal List<CloudSyncStep> Settle(CloudSyncControl control, CloudTransportReported reported) => settle(control, reported);

    /// A status: while the person decides, the transport does not speak.
    private static Func<CloudSyncControl, CloudTransportReported, List<CloudSyncStep>> Status(
        Func<CloudSyncControl, CloudTransportReported, List<CloudSyncStep>> settle) =>
        (control, reported) => control.Conflict is not null ? [] : settle(control, reported);

    private static Func<CloudSyncControl, CloudTransportReported, List<CloudSyncStep>> Status(
        Action<CloudSyncControl, CloudTransportReported> settle) =>
        Status((control, reported) => {
            settle(control, reported);
            return [];
        });

    private static List<CloudSyncStep> Succeeded(CloudSyncControl control) {
        control.LastSuccessAt = control.Clock.Now;
        return control.ClearRecoveredFailure();
    }

    private static List<CloudSyncStep> RestartForAccount(CloudSyncControl control) {
        // The transport restarts against the account signed in now.
        control.IsTransportLive = false;
        control.Attempt++;
        control.Conflict = null;
        control.AccountRestartRequested = true;
        control.Phase = CloudSyncPhase.Checking;
        var steps = new List<CloudSyncStep> { control.Step(CloudSyncStepKind.StopTransport) };
        steps.AddRange(control.AccountRestartIfDue());
        return steps;
    }

    #endregion
}
