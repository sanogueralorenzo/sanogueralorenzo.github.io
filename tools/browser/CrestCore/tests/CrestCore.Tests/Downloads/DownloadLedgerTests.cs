using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class DownloadLedgerTests {
    private static readonly Guid Work = Guid.NewGuid(), Personal = Guid.NewGuid();
    private static readonly DateTimeOffset Epoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);
    private static readonly TimeSpan Day = TimeSpan.FromDays(1);

    private static DateTimeOffset At(double seconds) => Epoch.AddSeconds(seconds);

    private static Guid Begin(DownloadLedger ledger, Guid profile, string filename = "file.pdf", DateTimeOffset? createdAt = null,
        bool acknowledged = false) => ledger.Begin(Guid.NewGuid(), profile, filename, createdAt ?? Epoch, acknowledged).Id;

    [Fact]
    public void NewDownloadsAreNewestFirstAndKeepTheirProfileAndCreationTime() {
        var ledger = new DownloadLedger();
        var first = Begin(ledger, Work, "first.pdf", At(100));
        var second = Begin(ledger, Personal, "second.pdf", At(200));

        Assert.Equal([second, first], ledger.Items.Select(item => item.Id));
        Assert.Equal([At(200), At(100)], ledger.Items.Select(item => item.CreatedAt));
        Assert.Equal([Work, Personal], [ledger.Items[1].ProfileId, ledger.Items[0].ProfileId]);
        Assert.All(ledger.Items, item => Assert.Equal(DownloadPhase.Preparing, item.Phase));
        var duplicate = Assert.Throws<Rejected>(() => ledger.Begin(first, Work, "again.pdf", At(300), false));
        Assert.IsType<DuplicateDownload>(duplicate.Rejection);
        Assert.IsType<InvalidDownloadIdentity>(Assert.Throws<Rejected>(() => ledger.Begin(Guid.Empty, Work, "a.pdf", Epoch, false)).Rejection);
        Assert.Equal(new InvalidDownloadText(DownloadTextField.Filename),
            Assert.Throws<Rejected>(() => ledger.Begin(Guid.NewGuid(), Work, "", Epoch, false)).Rejection);
    }

    [Fact]
    public void RiskyDownloadWaitsForApprovalUnderItsSanitizedNameAndCanBeCanceled() {
        var ledger = new DownloadLedger();
        var id = Begin(ledger, Work, "dangerous.command");
        var assessment = new DownloadRiskAssessment("system-update.command", [DownloadRiskReason.ExecutableOrInstaller]);

        var item = ledger.AssessRisk(id, assessment)!;
        Assert.Equal(DownloadPhase.AwaitingApproval, item.Phase);
        Assert.Equal("system-update.command", item.Filename);
        Assert.Same(assessment, item.Risk);

        var canceled = ledger.Cancel(id, "Canceled for safety.")!;
        Assert.Equal(DownloadPhase.Canceled, canceled.Phase);
        Assert.Equal("Canceled for safety.", canceled.Message);
    }

    [Fact]
    public void AnOrdinaryAssessmentKeepsTheTransferMoving() {
        var ledger = new DownloadLedger();
        var id = Begin(ledger, Work, "report");
        Assert.Equal(DownloadPhase.Preparing, ledger.AssessRisk(id, new("report.pdf", []))!.Phase);
        var downloading = ledger.SetDestination(id, "file:///Downloads/report%201.pdf", "report 1.pdf")!;
        Assert.Equal(DownloadPhase.Downloading, downloading.Phase);
        Assert.Equal("report 1.pdf", downloading.Filename);
    }

    [Fact]
    public void ProgressIsClampedAndNeverMovesBackwards() {
        var ledger = new DownloadLedger();
        var id = Begin(ledger, Work);
        var telemetry = new DownloadTelemetry(10, 100, 5, 18, false);
        Assert.Equal(0.6, ledger.RecordTransfer(id, telemetry, 0.6)!.Progress);
        Assert.Equal(0.6, ledger.RecordTransfer(id, telemetry, 0.4)!.Progress);
        Assert.Equal(1, ledger.RecordTransfer(id, telemetry, 7)!.Progress);
        Assert.Throws<Rejected>(() => ledger.RecordTransfer(id, telemetry, double.NaN));
        Assert.Throws<Rejected>(() => ledger.RecordTransfer(id, telemetry with { BytesReceived = -1 }, 0.5));
    }

    [Fact]
    public void FinishingStopsTelemetryAtTheBytesActuallyWritten() {
        var ledger = new DownloadLedger();
        var id = Begin(ledger, Work);
        ledger.RecordTransfer(id, new(400, 1_000, 50, 12, false), 0.4);

        var finished = ledger.Finish(id, 900)!;

        Assert.Equal(DownloadPhase.Finished, finished.Phase);
        Assert.Equal(1, finished.Progress);
        Assert.Equal(new DownloadTelemetry(900, 900, null, null, false), finished.Telemetry);
        var failed = ledger.Fail(Begin(ledger, Work), DownloadFailure.Network, "Network lost.")!;
        Assert.Equal(new DownloadTelemetry(0, null, null, null, false), failed.Telemetry);
    }

    [Fact]
    public void FinalRecordsIgnoreLateEngineEvents() {
        var ledger = new DownloadLedger();
        var id = Begin(ledger, Work);
        ledger.Cancel(id, "Canceled.");

        Assert.Null(ledger.Finish(id, 10));
        Assert.Null(ledger.RecordTransfer(id, DownloadTelemetry.Empty, 1));
        Assert.Null(ledger.SetDestination(id, "file:///late.pdf", "late.pdf"));
        Assert.Null(ledger.AssessRisk(id, new("late.pdf", [DownloadRiskReason.DeceptiveFilename])));
        Assert.Null(ledger.AwaitApproval(id));
        Assert.Null(ledger.Fail(id, DownloadFailure.Interrupted, "Late failure."));
        Assert.Null(ledger.BlockAutomaticDownload(id));
        Assert.Null(ledger.Restart(id));
        Assert.Equal(DownloadPhase.Canceled, ledger.Items[0].Phase);
        Assert.Null(ledger.Finish(Guid.NewGuid(), null));
    }

    [Fact]
    public void BlockedAutomaticDownloadRestartsFromNothingOrFailsWhenItCannotBeReplayed() {
        var ledger = new DownloadLedger();
        var id = Begin(ledger, Work, "Emerald.dmg");
        ledger.AssessRisk(id, new("Emerald.dmg", [DownloadRiskReason.ExecutableOrInstaller]));
        ledger.SetDestination(id, "file:///Emerald.dmg", "Emerald.dmg");
        ledger.AcknowledgeProfile(Work);
        Assert.Equal(DownloadPhase.BlockedAutomaticDownload, ledger.BlockAutomaticDownload(id)!.Phase);
        Assert.Null(ledger.Finish(id, null));

        var restarted = ledger.Restart(id)!;
        Assert.Equal(DownloadPhase.Preparing, restarted.Phase);
        Assert.Equal(0, restarted.Progress);
        Assert.Null(restarted.Destination);
        Assert.Null(restarted.Risk);
        Assert.False(restarted.IsAcknowledged);
        Assert.Null(ledger.Restart(id));

        ledger.BlockAutomaticDownload(id);
        var failed = ledger.Fail(id, reason: null, "Reload the original page, then try the download again.")!;
        Assert.Equal(DownloadPhase.Failed, failed.Phase);
    }

    [Fact]
    public void OpeningDownloadsAcknowledgesTheBadgeWithoutClearingHistory() {
        var ledger = new DownloadLedger();
        var first = Begin(ledger, Work);
        var second = Begin(ledger, Work);
        var other = Begin(ledger, Personal);
        var restored = Begin(ledger, Work, acknowledged: true);

        Assert.Equal([second, first], ledger.AcknowledgeProfile(Work).Select(item => item.Id));
        Assert.Empty(ledger.AcknowledgeProfile(Work));
        Assert.Equal(4, ledger.Items.Count);
        Assert.False(ledger.Items.Single(item => item.Id == other).IsAcknowledged);
        Assert.True(ledger.Items.Single(item => item.Id == restored).IsAcknowledged);

        var third = Begin(ledger, Work);
        Assert.Equal([third], ledger.Items.Where(item => item.ProfileId == Work && !item.IsAcknowledged).Select(item => item.Id));
    }

    [Fact]
    public void RemovingAProfilesRecordsPreservesEveryOtherProfile() {
        var ledger = new DownloadLedger();
        var removed = Begin(ledger, Work);
        var kept = Begin(ledger, Personal);

        Assert.Equal([removed], ledger.RemoveProfile(Work));
        Assert.Equal([kept], ledger.Items.Select(item => item.Id));
        Assert.True(ledger.Remove(kept));
        Assert.False(ledger.Remove(kept));
        Assert.Empty(ledger.Items);
    }

    [Fact]
    public void ExpiryIsProfileScopedStrictAndNeverRemovesLiveTransfers() {
        var ledger = new DownloadLedger();
        DateTimeOffset now = Epoch + 1_000 * Day;
        TimeSpan lifetime = 30 * Day;
        var expired = Begin(ledger, Work, createdAt: now - lifetime - TimeSpan.FromSeconds(1));
        ledger.Finish(expired, null);
        var boundary = Begin(ledger, Work, createdAt: now - lifetime);
        ledger.Cancel(boundary, "Canceled.");
        var active = Begin(ledger, Work, createdAt: now - lifetime - TimeSpan.FromSeconds(1));
        var blocked = Begin(ledger, Work, createdAt: now - lifetime - TimeSpan.FromSeconds(1));
        ledger.BlockAutomaticDownload(blocked);
        var otherProfile = Begin(ledger, Personal, createdAt: Epoch);
        ledger.Finish(otherProfile, null);

        var removed = ledger.RemoveExpired([new(Work, lifetime)], now);

        Assert.Equal([blocked, expired], removed);
        Assert.Equal([otherProfile, active, boundary], ledger.Items.Select(item => item.Id));
    }

    [Fact]
    public void TheShortestRetentionOfSpacesSharingAProfileWinsAndForeverKeepsRecords() {
        var ledger = new DownloadLedger();
        DateTimeOffset now = Epoch + 1_000 * Day;
        var weekOld = Begin(ledger, Work, createdAt: now - 8 * Day);
        ledger.Finish(weekOld, null);
        var ancient = Begin(ledger, Personal, createdAt: Epoch);
        ledger.Finish(ancient, null);

        Assert.Empty(ledger.RemoveExpired([new(Work, 30 * Day), new(Work, null), new(Personal, null)], now));
        Assert.Equal([weekOld], ledger.RemoveExpired([new(Work, 30 * Day), new(Work, 7 * Day), new(Work, null)], now));
        Assert.Equal([ancient], ledger.Items.Select(item => item.Id));
        Assert.IsType<InvalidRetentionLifetime>(Assert.Throws<Rejected>(() => ledger.RemoveExpired([new(Work, -Day)], now)).Rejection);
    }
}
