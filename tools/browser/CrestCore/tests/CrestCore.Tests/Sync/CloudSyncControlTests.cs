using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// What iCloud sync does next on this device: how a start checks the
/// entitlement, the account, the seed and a waiting account decision, when an
/// account change waits for the person and what their choice applies, when a
/// sync or a pull counts as a success, and when a failed launch is retried.
public sealed partial class BrowserContractsTests {
    /// A core with iCloud sync configured and on, its transport state opened.
    private static CrestApp SyncingApp(bool awaitsAccountDecision = false, bool canReachCloud = true) {
        var app = new CrestApp();
        app.Send(new OpenCloudTransport(TransportSchema, Legacy: null));
        if (awaitsAccountDecision) app.Send(new ObserveCloudAccountChange(CloudAccountTransition.SwitchAccounts));
        app.Send(new ConfigureCloudSync(IsEnabled: true, canReachCloud));
        return app;
    }

    private static (CloudSyncStatus Status, CloudSyncStep[] Steps) Advance(CrestApp app, CloudSyncControlIntent intent) {
        var advanced = Assert.Single(app.Send(intent).OfType<CloudSyncAdvanced>());
        return (advanced.Status, [.. advanced.Steps]);
    }

    private static CloudSyncStepKind[] Kinds(CloudSyncStep[] steps) => [.. steps.Select(step => step.Kind)];

    /// Starts sync against an available account up to a live transport, and
    /// answers the start's attempt.
    private static long StartTransport(CrestApp app) {
        var (_, steps) = Advance(app, new StartCloudSync());
        long start = Assert.Single(steps).Attempt;
        Advance(app, new CloudEntitlementChecked(start, Granted: true));
        var (_, started) = Advance(app, new CloudAccountChecked(start, CloudAccountState.Available));
        Assert.Equal([CloudSyncStepKind.StartTransport], Kinds(started));
        Advance(app, new CloudTransportStarted(start));
        Advance(app, new CloudTransportReported(start, CloudTransportReport.Idle, null, 0, false));
        return start;
    }

    /// A running sync is not up to date while this device's journal holds
    /// records iCloud has not saved: it reads as waiting to upload until the
    /// cloud saves them.
    [Fact]
    public void ARunningSyncWaitsToUploadUntilTheCloudSavesTheJournalsRecords() {
        using var directory = new StorageDirectory();
        using var stored = StoredSyncing(directory, SavedSession().Document);
        var app = stored.App;
        app.Send(new OpenCloudTransport(TransportSchema, Legacy: null));
        app.Send(new ConfigureCloudSync(IsEnabled: true, CanReachCloud: true));
        long start = StartTransport(app);
        var pending = app.Query(new PendingUploads()).Records;
        Assert.NotEmpty(pending);
        Assert.Equal(CloudSyncPhase.WaitingToUpload, app.Query(new CloudSync()).Phase);

        var saved = app.Query(new RecordsToUpload(pending)).Records;
        app.Send(new AcknowledgeUploads([.. saved.Select(record => new UploadedRecord(new(record.Kind, record.Id), record.Version))]));
        var status = Advance(app, new CloudTransportReported(start, CloudTransportReport.Uploaded, null, saved.Count, false)).Status;

        Assert.Equal(CloudSyncPhase.Ready, status.Phase);
    }

    [Fact]
    public void AStartThatCannotReachCloudKitFailsAndNamesWhy() {
        using var app = SyncingApp(canReachCloud: false);
        var (status, steps) = Advance(app, new StartCloudSync());
        Assert.Equal((CloudSyncPhase.Failed, CloudSyncProblem.NotConfigured, CloudAccountState.CouldNotDetermine),
            (status.Phase, status.Problem, status.Account));
        Assert.Empty(steps);

        using var unentitled = SyncingApp();
        long start = Advance(unentitled, new StartCloudSync()).Steps[0].Attempt;
        (status, steps) = Advance(unentitled, new CloudEntitlementChecked(start, Granted: false));
        Assert.Equal((CloudSyncPhase.Failed, CloudSyncProblem.EntitlementMissing), (status.Phase, status.Problem));
        // A failed launch is retried, as one that could not reach iCloud is.
        Assert.Equal([CloudSyncStepKind.ScheduleRetry], Kinds(steps));
    }

    [Fact]
    public void AnAvailableAccountStartsTheTransportWithoutASyncAndItsActivityCounts() {
        using var app = SyncingApp();
        var (_, steps) = Advance(app, new StartCloudSync());
        Assert.Equal([CloudSyncStepKind.CheckEntitlement], Kinds(steps));
        long start = steps[0].Attempt;
        var (status, checking) = Advance(app, new CloudEntitlementChecked(start, Granted: true));
        Assert.Equal([CloudSyncStepKind.CheckAccount], Kinds(checking));
        Assert.Equal(CloudSyncPhase.Checking, status.Phase);
        Assert.NotNull(status.LastAttemptAt);
        Assert.Equal([CloudSyncStepKind.StartTransport], Kinds(Advance(app, new CloudAccountChecked(start, CloudAccountState.Available)).Steps));
        Assert.Empty(Advance(app, new CloudTransportStarted(start)).Steps);
        status = Advance(app, new CloudTransportReported(start, CloudTransportReport.Idle, null, 0, false)).Status;
        Assert.Equal((CloudSyncPhase.Ready, (DateTimeOffset?)null), (status.Phase, status.LastSuccessAt));

        Advance(app, new CloudTransportReported(start, CloudTransportReport.Fetched, null, 4, false));
        status = Advance(app, new CloudTransportReported(start, CloudTransportReport.Uploaded, null, 3, false)).Status;
        Assert.Equal((4, 3), (status.LastFetchedRecords, status.LastUploadedRecords));
        Assert.NotNull(status.LastSuccessAt);
        Assert.Equal([CloudSyncStepKind.NotifyTransport], Kinds(Advance(app, new NotifyCloudLocalChanges()).Steps));
    }

    [Fact]
    public void AnUnavailableAccountWaitsAndRetriesALaunchOnlyAFewTimes() {
        using var app = SyncingApp();
        for (int retry = 1; retry <= 4; retry++) {
            long start = Advance(app, retry == 1 ? new StartCloudSync() : new RetryCloudSync()).Steps.Single().Attempt;
            Advance(app, new CloudEntitlementChecked(start, Granted: true));
            var (status, steps) = Advance(app, new CloudAccountChecked(start, CloudAccountState.NoAccount));
            Assert.Equal((CloudSyncPhase.WaitingForAccount, CloudAccountState.NoAccount), (status.Phase, status.Account));
            Assert.Equal(retry <= 3 ? [CloudSyncStepKind.ScheduleRetry] : [], Kinds(steps));
        }
    }

    [Fact]
    public void ALaunchThatFailedTransientlyRetriesAndReachesTheTransport() {
        using var app = SyncingApp();
        long start = Advance(app, new StartCloudSync()).Steps[0].Attempt;
        Advance(app, new CloudEntitlementChecked(start, Granted: true));
        var (status, steps) = Advance(app, new CloudStepFailed(start, CloudSyncStepKind.CheckAccount, "Crest can’t reach iCloud right now.", null));
        Assert.Equal((CloudSyncPhase.Failed, "Crest can’t reach iCloud right now."), (status.Phase, status.FailureMessage));
        Assert.Equal([CloudSyncStepKind.ScheduleRetry], Kinds(steps));

        long retried = Assert.Single(Advance(app, new RetryCloudSync()).Steps).Attempt;
        Advance(app, new CloudEntitlementChecked(retried, Granted: true));
        Assert.Equal([CloudSyncStepKind.StartTransport], Kinds(Advance(app, new CloudAccountChecked(retried, CloudAccountState.Available)).Steps));
    }

    [Fact]
    public void AnAccountDecisionComparesContentAndOnlyADeviceWithNothingTakesTheCloud() {
        using var refused = SyncingApp(awaitsAccountDecision: true);
        long start = Advance(refused, new StartCloudSync()).Steps[0].Attempt;
        Advance(refused, new CloudEntitlementChecked(start, Granted: true));
        Assert.Equal([CloudSyncStepKind.CompareContent], Kinds(Advance(refused, new CloudAccountChecked(start, CloudAccountState.Available)).Steps));
        // A comparison the core refuses never reads as a device with nothing to keep.
        var (status, steps) = Advance(refused, new CloudStepFailed(start, CloudSyncStepKind.CompareContent, "refused", 3));
        Assert.Equal((CloudSyncPhase.Failed, (CloudContentComparison?)null), (status.Phase, status.Conflict));
        Assert.DoesNotContain(CloudSyncStepKind.TakeCloudContent, Kinds(steps));
        Assert.True(refused.Query(new CloudTransport()).AwaitsAccountDecision);

        foreach (var (comparison, outcome) in new (CloudContentComparison, CloudSyncStepKind?)[] {
            (new(Matches: false, DeviceRecords: 5, CloudRecords: 3, DeviceSpaces: 2, CloudSpaces: 1), null),
            (new(Matches: false, DeviceRecords: 0, CloudRecords: 3, DeviceSpaces: 0, CloudSpaces: 1), CloudSyncStepKind.TakeCloudContent),
            (new(Matches: true, DeviceRecords: 5, CloudRecords: 5, DeviceSpaces: 2, CloudSpaces: 2), CloudSyncStepKind.StartTransport),
            (new(Matches: true, DeviceRecords: 0, CloudRecords: 0, DeviceSpaces: 0, CloudSpaces: 0), CloudSyncStepKind.StartTransport)
        }) {
            using var app = SyncingApp(awaitsAccountDecision: true);
            long attempt = Advance(app, new StartCloudSync()).Steps[0].Attempt;
            Advance(app, new CloudEntitlementChecked(attempt, Granted: true));
            Advance(app, new CloudAccountChecked(attempt, CloudAccountState.Available));
            (status, steps) = Advance(app, new CloudContentCompared(attempt, comparison.CloudRecords, comparison));
            Assert.Equal(comparison.CloudRecords, status.ObservedCloudRecords);
            if (outcome is null) {
                Assert.Equal((CloudSyncPhase.NeedsReconciliation, comparison), (status.Phase, status.Conflict));
                Assert.Empty(steps);
                Assert.True(app.Query(new CloudTransport()).AwaitsAccountDecision);
                continue;
            }
            Assert.Equal([outcome], Kinds(steps));
            if (outcome == CloudSyncStepKind.TakeCloudContent)
                Assert.Equal([CloudSyncStepKind.StartTransport], Kinds(Advance(app, new CloudContentTaken(attempt)).Steps));
            Assert.False(app.Query(new CloudTransport()).AwaitsAccountDecision);
        }
    }

    [Fact]
    public void ThePersonsChoiceAppliesItsCopyAndStartsTheTransportOverIt() {
        foreach (bool usesCloud in new[] { true, false }) {
            using var app = SyncingApp(awaitsAccountDecision: true);
            long start = Advance(app, new StartCloudSync()).Steps[0].Attempt;
            Advance(app, new CloudEntitlementChecked(start, Granted: true));
            Advance(app, new CloudAccountChecked(start, CloudAccountState.Available));
            Advance(app, new CloudContentCompared(start, 3, new(Matches: false, DeviceRecords: 5, CloudRecords: 3, DeviceSpaces: 2, CloudSpaces: 1)));

            var (status, steps) = Advance(app, new ChooseCloudCopy(usesCloud));
            var apply = Assert.Single(steps);
            Assert.Equal((CloudSyncStepKind.ApplyChosenCopy, usesCloud, CloudSyncPhase.Syncing), (apply.Kind, apply.UsesCloud, status.Phase));
            (status, steps) = Advance(app, new CloudCopyApplied(apply.Attempt, usesCloud, 3));
            Assert.Equal([CloudSyncStepKind.StartTransport], Kinds(steps));
            Assert.Null(status.Conflict);
            var transport = app.Query(new CloudTransport());
            Assert.Equal((false, !usesCloud), (transport.AwaitsAccountDecision, transport.OverwritesCloud));
            Advance(app, new CloudTransportStarted(apply.Attempt));
            Assert.Equal(CloudSyncPhase.Ready,
                Advance(app, new CloudTransportReported(apply.Attempt, CloudTransportReport.Idle, null, 0, false)).Status.Phase);
        }
    }

    [Fact]
    public void AFirstLaunchReplacesItsDisposableSeedBeforeTheTransportStarts() {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        using var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        app.Send(Adoption(document));
        _ = TestWorkspaces.OpenStored(app);
        app.Send(new OpenCloudTransport(TransportSchema, Legacy: null));
        app.Send(new SaveCloudEngineState([1]));
        app.Send(new ConfigureCloudSync(IsEnabled: true, CanReachCloud: true));
        long start = Advance(app, new StartCloudSync()).Steps[0].Attempt;
        Advance(app, new CloudEntitlementChecked(start, Granted: true));
        Assert.Equal([CloudSyncStepKind.ReplaceSeed], Kinds(Advance(app, new CloudAccountChecked(start, CloudAccountState.Available)).Steps));
        var (status, steps) = Advance(app, new CloudSeedReplaced(start, 4));
        Assert.Equal([CloudSyncStepKind.StartTransport], Kinds(steps));
        Assert.Equal(4, status.ObservedCloudRecords);
        Assert.Null(app.Query(new CloudTransport()).EngineState);
    }

    [Fact]
    public void AnAccountChangeDropsTheTransportAndRestartsAgainstTheCurrentAccount() {
        using var app = SyncingApp();
        long start = StartTransport(app);
        var (status, steps) = Advance(app, new CloudTransportReported(start, CloudTransportReport.AccountChanged, null, 0, false));
        Assert.Equal([CloudSyncStepKind.StopTransport, CloudSyncStepKind.RestartAfterAccountChange], Kinds(steps));
        Assert.Equal(CloudSyncPhase.Checking, status.Phase);
        // The old transport's reports no longer count.
        Assert.Equal(CloudSyncPhase.Checking,
            Advance(app, new CloudTransportReported(start, CloudTransportReport.Idle, null, 0, false)).Status.Phase);
        long restarted = Assert.Single(Advance(app, new RestartCloudSyncAfterAccountChange()).Steps).Attempt;
        Assert.NotEqual(start, restarted);

        // A notification restarts a device that was signed out, on its own.
        using var signedOut = SyncingApp();
        long waiting = Advance(signedOut, new StartCloudSync()).Steps[0].Attempt;
        Advance(signedOut, new CloudEntitlementChecked(waiting, Granted: true));
        Advance(signedOut, new CloudAccountChecked(waiting, CloudAccountState.NoAccount));
        (status, steps) = Advance(signedOut, new ObserveCloudAccountAvailability());
        Assert.Equal([CloudSyncStepKind.CancelRetry, CloudSyncStepKind.CheckEntitlement], Kinds(steps));
        Assert.Equal(CloudSyncPhase.Checking, status.Phase);
    }

    [Fact]
    public void TurningSyncOffStopsTheTransportAndStartsItsStateOverUnlessADecisionWaits() {
        using var waiting = SyncingApp(awaitsAccountDecision: true);
        Assert.Equal(CloudSyncPhase.Disabled, Advance(waiting, new SetCloudSyncEnabled(false)).Status.Phase);
        Assert.True(waiting.Query(new CloudTransport()).AwaitsAccountDecision);

        using var app = SyncingApp();
        app.Send(new SaveCloudEngineState([1]));
        StartTransport(app);
        var (status, steps) = Advance(app, new SetCloudSyncEnabled(false));
        Assert.Equal([CloudSyncStepKind.StopTransport], Kinds(steps));
        Assert.Equal(CloudSyncPhase.Disabled, status.Phase);
        Assert.Null(app.Query(new CloudTransport()).EngineState);
        Assert.Empty(Advance(app, new RequestCloudPull()).Steps);
        Assert.Empty(Advance(app, new RequestCloudSync()).Steps);
    }

    [Fact]
    public void TurningSyncOffBeforeTheInstalledStateIsAdoptedStartsItOverAtTheAdoption() {
        foreach (string? reason in new[] { null, "accountChange" }) {
            using var app = new CrestApp();
            app.Send(new ConfigureCloudSync(IsEnabled: true, CanReachCloud: true));
            Advance(app, new SetCloudSyncEnabled(false));
            var adopted = Transport(app, new OpenCloudTransport(TransportSchema, LegacyTransportFile(reason: reason)));
            Assert.Equal(reason is not null, adopted.AwaitsAccountDecision);
            Assert.Equal(reason is not null, adopted.EngineState is not null);
        }
    }

    [Fact]
    public void TurningSyncOffDuringALaunchLeavesNoLiveTransport() {
        using var app = SyncingApp();
        long start = Advance(app, new StartCloudSync()).Steps[0].Attempt;
        Advance(app, new CloudEntitlementChecked(start, Granted: true));
        Assert.Empty(Advance(app, new SetCloudSyncEnabled(false)).Steps);
        var (status, steps) = Advance(app, new CloudAccountChecked(start, CloudAccountState.Available));
        Assert.Empty(steps);
        Assert.Equal((CloudSyncPhase.Disabled, (DateTimeOffset?)null), (status.Phase, status.LastSuccessAt));

        // A transport the launch was starting is stopped once it started.
        using var starting = SyncingApp();
        start = Advance(starting, new StartCloudSync()).Steps[0].Attempt;
        Advance(starting, new CloudEntitlementChecked(start, Granted: true));
        Advance(starting, new CloudAccountChecked(start, CloudAccountState.Available));
        Assert.Equal([CloudSyncStepKind.StopTransport], Kinds(Advance(starting, new SetCloudSyncEnabled(false)).Steps));
        Assert.Equal([CloudSyncStepKind.DiscardStartedTransport], Kinds(Advance(starting, new CloudTransportStarted(start)).Steps));
    }

    [Fact]
    public void AFailedSyncIsNeitherUpToDateNorRetriedWhileTheTransportRuns() {
        using var app = SyncingApp();
        long start = StartTransport(app);
        Assert.Equal([CloudSyncStepKind.SyncTransport], Kinds(Advance(app, new RequestCloudSync()).Steps));
        var (status, steps) = Advance(app, new CloudStepFailed(start, CloudSyncStepKind.SyncTransport, "boom", null));
        Assert.Equal((CloudSyncPhase.Failed, "boom", (DateTimeOffset?)null), (status.Phase, status.FailureMessage, status.LastSuccessAt));
        Assert.Empty(steps);

        // Activity from the transport proves it recovered.
        status = Advance(app, new CloudTransportReported(start, CloudTransportReport.Uploaded, null, 2, false)).Status;
        Assert.Equal((CloudSyncPhase.Ready, (string?)null, 2), (status.Phase, status.FailureMessage, status.LastUploadedRecords));
        Assert.NotNull(status.LastSuccessAt);

        // A sync that finished while this device's edits could not be saved is no success.
        Advance(app, new RequestCloudSync());
        status = Advance(app, new CloudTransportSynced(start, LocalChangesUnsaved: true)).Status;
        Assert.Equal((CloudSyncPhase.Failed, CloudSyncProblem.LocalChangesUnsaved), (status.Phase, status.Problem));
    }

    [Fact]
    public void SkippedRecordsAndRemovedCloudDataReachTheStatus() {
        using var app = SyncingApp();
        long start = StartTransport(app);
        Advance(app, new CloudTransportReported(start, CloudTransportReport.SkippedRecords, null, 2, RequiresAppUpdate: true));
        var status = Advance(app, new CloudTransportReported(start, CloudTransportReport.CloudDataRemoved, null, 0, false)).Status;
        Assert.Equal((2, true, true), (status.SkippedRecords, status.RequiresAppUpdate, status.CloudDataRemoved));
    }

    [Fact]
    public void APullCountsItsSnapshotAndNothingAfterSyncIsTurnedOff() {
        using var app = SyncingApp();
        long start = StartTransport(app);
        Assert.Equal([CloudSyncStepKind.PullTransport], Kinds(Advance(app, new RequestCloudPull()).Steps));
        var status = Advance(app, new CloudTransportPulled(start, 4, LocalChangesUnsaved: false)).Status;
        Assert.Equal((4, 4, CloudSyncPhase.Ready), (status.LastFetchedRecords, status.ObservedCloudRecords, status.Phase));
        Assert.NotNull(status.LastSuccessAt);

        Advance(app, new SetCloudSyncEnabled(false));
        status = Advance(app, new CloudTransportReported(start, CloudTransportReport.Fetched, null, 99, false)).Status;
        Assert.Equal((4, CloudSyncPhase.Disabled), (status.LastFetchedRecords, status.Phase));

        // A pull suspended when sync turned off reports nothing when it ends.
        using var suspended = SyncingApp();
        start = StartTransport(suspended);
        Advance(suspended, new RequestCloudPull());
        Advance(suspended, new SetCloudSyncEnabled(false));
        status = Advance(suspended, new CloudTransportPulled(start, 4, LocalChangesUnsaved: false)).Status;
        Assert.Equal(((DateTimeOffset?)null, (int?)null, CloudSyncPhase.Disabled), (status.LastSuccessAt, status.ObservedCloudRecords, status.Phase));

        // A failed pull reports no success.
        using var failing = SyncingApp();
        start = StartTransport(failing);
        Advance(failing, new RequestCloudPull());
        status = Advance(failing, new CloudStepFailed(start, CloudSyncStepKind.PullTransport, "unavailable", null)).Status;
        Assert.Equal((CloudSyncPhase.Failed, (DateTimeOffset?)null, (int?)null), (status.Phase, status.LastSuccessAt, status.ObservedCloudRecords));
    }
}
