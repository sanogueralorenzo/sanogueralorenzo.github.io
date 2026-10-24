namespace CrestCore.Contracts;

/// What the platform does for one step of iCloud sync.
///
/// A kind travels as its index in `All`, so `All` is append-only.
public sealed class CloudSyncStepKind {
    #region Types

    /// The platform takes each step with different work, so the one place that
    /// takes a step switches over its kind.
    public enum Kinds {
        CheckEntitlement,
        CheckAccount,
        ReplaceSeed,
        CompareContent,
        TakeCloudContent,
        ApplyChosenCopy,
        StartTransport,
        DiscardStartedTransport,
        StopTransport,
        SyncTransport,
        PullTransport,
        NotifyTransport,
        ScheduleRetry,
        CancelRetry,
        RestartAfterAccountChange
    }

    #endregion

    #region Static Variables

    /// Asks whether this build holds the entitlement for Crest's container;
    /// reports `CloudEntitlementChecked`.
    public static readonly CloudSyncStepKind CheckEntitlement = new(Kinds.CheckEntitlement, name: "checkEntitlement");
    /// Asks iCloud for the account's state; reports `CloudAccountChecked`.
    public static readonly CloudSyncStepKind CheckAccount = new(Kinds.CheckAccount, name: "checkAccount");
    /// Loads the cloud's records and replaces the disposable seed with them;
    /// reports `CloudSeedReplaced`.
    public static readonly CloudSyncStepKind ReplaceSeed = new(Kinds.ReplaceSeed, name: "replaceSeed");
    /// Loads the cloud's records and asks the core how they compare with this
    /// device's; reports `CloudContentCompared`.
    public static readonly CloudSyncStepKind CompareContent = new(Kinds.CompareContent, name: "compareContent");
    /// Replaces this device's content with the records the comparison loaded;
    /// reports `CloudContentTaken`.
    public static readonly CloudSyncStepKind TakeCloudContent = new(Kinds.TakeCloudContent, name: "takeCloudContent");
    /// Loads the cloud's records and applies the copy the person chose:
    /// the cloud's in place of this device's, or this device's over the
    /// cloud's; reports `CloudCopyApplied`.
    public static readonly CloudSyncStepKind ApplyChosenCopy = new(Kinds.ApplyChosenCopy, name: "applyChosenCopy");
    /// Creates and starts the transport; reports `CloudTransportStarted`.
    public static readonly CloudSyncStepKind StartTransport = new(Kinds.StartTransport, name: "startTransport");
    /// Stops the transport that was started for a start no longer current.
    public static readonly CloudSyncStepKind DiscardStartedTransport = new(Kinds.DiscardStartedTransport, name: "discardStartedTransport");
    /// Stops and drops the current transport.
    public static readonly CloudSyncStepKind StopTransport = new(Kinds.StopTransport, name: "stopTransport");
    /// Has the transport fetch and send now; reports `CloudTransportSynced`.
    public static readonly CloudSyncStepKind SyncTransport = new(Kinds.SyncTransport, name: "syncTransport");
    /// Has the transport pull a full snapshot; reports `CloudTransportPulled`.
    public static readonly CloudSyncStepKind PullTransport = new(Kinds.PullTransport, name: "pullTransport");
    /// Tells the transport this device staged local changes.
    public static readonly CloudSyncStepKind NotifyTransport = new(Kinds.NotifyTransport, name: "notifyTransport");
    /// Sends `RetryCloudSync` after the platform's retry delay.
    public static readonly CloudSyncStepKind ScheduleRetry = new(Kinds.ScheduleRetry, name: "scheduleRetry");
    /// Cancels the retry scheduled before.
    public static readonly CloudSyncStepKind CancelRetry = new(Kinds.CancelRetry, name: "cancelRetry");
    /// Sends `RestartCloudSyncAfterAccountChange` once the current turn ends.
    public static readonly CloudSyncStepKind RestartAfterAccountChange =
        new(Kinds.RestartAfterAccountChange, name: "restartAfterAccountChange");

    public static IReadOnlyList<CloudSyncStepKind> All { get; } = [
        CheckEntitlement, CheckAccount, ReplaceSeed, CompareContent, TakeCloudContent, ApplyChosenCopy, StartTransport,
        DiscardStartedTransport, StopTransport, SyncTransport, PullTransport, NotifyTransport, ScheduleRetry, CancelRetry,
        RestartAfterAccountChange
    ];

    #endregion

    #region Variables

    public Kinds Kind { get; }
    public string Name { get; }

    #endregion

    #region Constructors

    private CloudSyncStepKind(Kinds kind, string name) {
        Kind = kind;
        Name = name;
    }

    #endregion
}
