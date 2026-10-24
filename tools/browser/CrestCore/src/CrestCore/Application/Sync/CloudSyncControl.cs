using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Decides what iCloud sync does on this device: when it starts, what a
/// start checks and in which order, when the first launch takes the cloud's
/// content, when an account change waits for the person and what their
/// choice applies, when a sync or a pull counts as a success, and when a
/// failed launch is retried. The platform takes the steps it answers, which
/// reach CloudKit and the transport, and reports what each came to; a result
/// for a start that is no longer current changes only what it must.
internal sealed class CloudSyncControl {
    #region Static Variables

    /// A launch that could not reach iCloud is retried this many times; a
    /// signed-out account heals through `ObserveCloudAccountAvailability`
    /// instead of through polling.
    private const int MaximumRetryAttempts = 3;

    #endregion

    #region Variables

    private readonly Lock gate = new();
    internal Lock Gate => gate;
    internal CloudTransportStore Transport { get; }
    internal IClock Clock { get; }
    /// Whether the session the core keeps in its file is still the disposable
    /// seed a first launch made, which the cloud's content replaces.
    internal Func<bool> SeedIsDisposable { get; }
    /// How many records the stored session's journal holds waiting to upload,
    /// read without the control's lock: the journal keeps a lock of its own.
    private readonly Func<int> pendingUploads;

    internal bool IsEnabled { get; set; } = true;
    internal bool CanReachCloud { get; set; }
    internal CloudAccountState Account { get; set; } = CloudAccountState.Checking;
    internal CloudSyncPhase Phase { get; set; } = CloudSyncPhase.Checking;
    internal CloudSyncProblem? Problem { get; set; }
    internal string? FailureMessage { get; set; }
    internal DateTimeOffset? LastAttemptAt { get; set; }
    internal DateTimeOffset? LastSuccessAt { get; set; }
    internal int LastFetched { get; set; }
    internal int LastUploaded { get; set; }
    internal int Skipped { get; set; }
    internal int? ObservedCloud { get; set; }
    internal CloudContentComparison? Conflict { get; set; }
    internal bool RequiresAppUpdate { get; set; }
    internal bool CloudDataRemoved { get; set; }

    /// The platform holds a transport, started or starting.
    internal bool IsTransportLive { get; set; }
    /// A start, sync, pull or choice is under way.
    internal bool IsRunning { get; set; }
    internal bool AccountRestartRequested { get; set; }
    /// The current start; results for an earlier one are stale.
    internal long Attempt { get; set; }
    internal bool RetryScheduled { get; set; }
    internal int RetryAttempts { get; set; }

    #endregion

    #region Constructors

    public CloudSyncControl(CloudTransportStore transport, IClock clock, Func<bool> seedIsDisposable, Func<int> pendingUploads) {
        ArgumentNullException.ThrowIfNull(transport);
        ArgumentNullException.ThrowIfNull(clock);
        ArgumentNullException.ThrowIfNull(seedIsDisposable);
        ArgumentNullException.ThrowIfNull(pendingUploads);
        Transport = transport;
        Clock = clock;
        SeedIsDisposable = seedIsDisposable;
        this.pendingUploads = pendingUploads;
    }

    #endregion

    #region Actions - Intents

    /// Runs one intent and answers the status it left with the steps the
    /// platform takes next. Throws `Rejected` when the transport's state
    /// cannot be saved.
    public IReadOnlyList<Change> Handle(CloudSyncControlIntent intent) {
        ArgumentNullException.ThrowIfNull(intent);
        int pending = pendingUploads();
        lock (gate) {
            var steps = intent.Steps(this);
            return [new CloudSyncAdvanced(Status(pending), steps)];
        }
    }

    /// Checks the entitlement, the account, the seed and a waiting account
    /// decision, in that order, then starts the transport.
    internal List<CloudSyncStep> Start() {
        if (!IsEnabled || IsRunning || IsTransportLive) return [];
        IsRunning = true;
        Attempt++;
        if (!CanReachCloud) {
            Phase = CloudSyncPhase.Failed;
            Problem = CloudSyncProblem.NotConfigured;
            FailureMessage = null;
            Account = CloudAccountState.CouldNotDetermine;
            return Finish();
        }
        return [Step(CloudSyncStepKind.CheckEntitlement)];
    }

    /// With an account decision waiting, this device's content is compared
    /// with the cloud's first.
    internal List<CloudSyncStep> AfterSeed(long start) {
        if (!Current(start)) return Finish();
        return Transport.AwaitsAccountDecision ? [Step(CloudSyncStepKind.CompareContent)] : StartTransport();
    }

    /// The transport starts over once this device took content; a start
    /// that is no longer current starts no transport.
    internal List<CloudSyncStep> ResetThenStart(long start, bool overwritesCloud) {
        if (!Reset(overwritesCloud, start) || !Current(start)) return Finish();
        return StartTransport();
    }

    /// Starts the transport unless one is already live. The start ends once
    /// it reports.
    internal List<CloudSyncStep> StartTransport() {
        if (IsTransportLive) return Finish();
        IsTransportLive = true;
        return [Step(CloudSyncStepKind.StartTransport)];
    }

    /// Has the running transport sync now, or starts sync when none runs.
    internal List<CloudSyncStep> SyncNow() {
        if (!IsEnabled || Conflict is not null || IsRunning) return [];
        if (!IsTransportLive) return Start();
        IsRunning = true;
        LastAttemptAt = Clock.Now;
        Phase = CloudSyncPhase.Syncing;
        return [Step(CloudSyncStepKind.SyncTransport)];
    }

    #endregion

    #region Actions - Outcomes

    /// A sync that finished counts as a success unless this device's own
    /// edits could not be staged or saved meanwhile.
    internal List<CloudSyncStep> RecordSuccess(bool localChangesUnsaved) {
        if (localChangesUnsaved) {
            Phase = CloudSyncPhase.Failed;
            Problem = CloudSyncProblem.LocalChangesUnsaved;
            FailureMessage = null;
            return [];
        }
        LastSuccessAt = Clock.Now;
        Phase = CloudSyncPhase.Ready;
        ClearFailure();
        RetryAttempts = 0;
        return CancelRetry();
    }

    /// Activity from a transport the system scheduler retried proves that
    /// it recovered, so an earlier error must not stay.
    internal List<CloudSyncStep> ClearRecoveredFailure() {
        if (IsRunning || !HasError) return [];
        Phase = CloudSyncPhase.Ready;
        ClearFailure();
        RetryAttempts = 0;
        return CancelRetry();
    }

    internal void Fail(string message) {
        FailureMessage = message;
        Problem = null;
        Phase = CloudSyncPhase.Failed;
    }

    internal void ClearFailure() {
        Problem = null;
        FailureMessage = null;
    }

    private bool HasError => FailureMessage is not null || Problem is { ReportsError: true };

    /// Starts the transport's state over; a save that fails fails `start`
    /// while it is current.
    internal bool Reset(bool overwritesCloud, long start) {
        try {
            Transport.Reset(overwritesCloud);
            return true;
        } catch (Rejected rejected) {
            if (Current(start)) Fail(rejected.Rejection is SaveFailed failed ? failed.Message : rejected.Rejection.GetType().Name);
            return false;
        }
    }

    /// What ending a start, sync, pull or choice leads to: a restart an
    /// account change asked for, or a retry of a launch that could not reach
    /// iCloud.
    internal List<CloudSyncStep> Finish() {
        IsRunning = false;
        var steps = AccountRestartIfDue();
        steps.AddRange(RetryIfDue());
        return steps;
    }

    internal List<CloudSyncStep> AccountRestartIfDue() =>
        AccountRestartRequested && !IsRunning ? [Step(CloudSyncStepKind.RestartAfterAccountChange)] : [];

    /// Retries a launch that ended without a working transport, a few times.
    private List<CloudSyncStep> RetryIfDue() {
        if (!IsEnabled || Conflict is not null || IsRunning || AccountRestartRequested || IsTransportLive || !CanReachCloud
            || RetryScheduled || RetryAttempts >= MaximumRetryAttempts || !Phase.IsRetryable) return [];
        RetryAttempts++;
        RetryScheduled = true;
        return [Step(CloudSyncStepKind.ScheduleRetry)];
    }

    internal List<CloudSyncStep> CancelRetry() {
        if (!RetryScheduled) return [];
        RetryScheduled = false;
        return [Step(CloudSyncStepKind.CancelRetry)];
    }

    internal bool Current(long start) => IsEnabled && start == Attempt;

    internal CloudSyncStep Step(CloudSyncStepKind kind) => new(kind, Attempt, UsesCloud: false);

    internal static CloudSyncStep Step(CloudSyncStepKind kind, long start) => new(kind, start, UsesCloud: false);

    #endregion

    #region Actions - Queries

    /// The status, showing the phase as it reads while `pendingUploads`
    /// records wait to upload.
    internal CloudSyncStatus Status(int pendingUploads) => new(IsEnabled, Account, Phase.Showing(pendingUploads), Problem, FailureMessage,
        LastAttemptAt, LastSuccessAt, LastFetched, LastUploaded, ObservedCloud, Conflict, Skipped, RequiresAppUpdate, CloudDataRemoved);

    /// How many records wait to upload, read without the control's lock.
    internal int PendingUploads() => pendingUploads();

    #endregion
}
