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

}
