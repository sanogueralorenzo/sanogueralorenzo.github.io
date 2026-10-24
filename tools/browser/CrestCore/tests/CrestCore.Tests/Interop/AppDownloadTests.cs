using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Native;

using Xunit;

namespace CrestCore.Tests;

/// The downloads area through the native app boundary: encoded intents in,
/// encoded changes or one rejection out.
public sealed class AppDownloadTests {
    private static readonly Guid Profile = Guid.NewGuid(), Other = Guid.NewGuid();
    private static readonly DateTimeOffset Epoch = new(2001, 1, 1, 0, 0, 0, TimeSpan.Zero);

    private static DownloadUpdated Updated(IReadOnlyList<Change> changes) => Assert.IsType<DownloadUpdated>(Assert.Single(changes));

    [Fact]
    public void IntentsAnswerTheRecordsTheyChangedWithTheirNewestFirstPositions() {
        using var app = new AppClient();
        Guid first = Guid.NewGuid(), second = Guid.NewGuid();
        var begun = Updated(app.Send(new BeginDownload(first, Profile, "a.pdf", Epoch.AddSeconds(10.5), false)));
        Assert.Equal((first, 0, DownloadPhase.Preparing, Epoch.AddSeconds(10.5)),
            (begun.Download.Id, begun.Position, begun.Download.Phase, begun.Download.CreatedAt));
        Assert.True(Updated(app.Send(new BeginDownload(second, Profile, "b.pdf", Epoch.AddSeconds(20), true))).Download.IsAcknowledged);

        var risky = Updated(app.Send(new AssessDownloadRisk(first,
            new("a.command", [DownloadRiskReason.ExecutableOrInstaller]))));
        Assert.Equal((1, DownloadPhase.AwaitingApproval, "a.command"), (risky.Position, risky.Download.Phase, risky.Download.Filename));
        Assert.Equal([DownloadRiskReason.ExecutableOrInstaller], risky.Download.Risk!.Reasons);

        var transfer = Updated(app.Send(new RecordDownloadTransfer(first,
            new(5_000_000_000, 10_000_000_000, 1e6, null, false), 0.5)));
        Assert.Equal(new DownloadTelemetry(5_000_000_000, 10_000_000_000, 1e6, null, false), transfer.Download.Telemetry);

        var canceled = Updated(app.Send(new CancelDownload(first, "Canceled.")));
        Assert.Equal((DownloadPhase.Canceled, "Canceled."), (canceled.Download.Phase, canceled.Download.Message));
        Assert.Empty(app.Send(new FinishDownload(first, null)));

        var acknowledged = Updated(app.Send(new AcknowledgeDownloads(Profile)));
        Assert.Equal((first, 1, true), (acknowledged.Download.Id, acknowledged.Position, acknowledged.Download.IsAcknowledged));
        Assert.Empty(app.Send(new AcknowledgeDownloads(Profile)));
    }

    [Fact]
    public void ARefusedIntentAnswersTheRuleItBrokeAndChangesNothing() {
        using var app = new AppClient();
        var id = Guid.NewGuid();
        app.Send(new BeginDownload(id, Profile, "a.pdf", Epoch, false));

        Assert.Equal(new DuplicateDownload(), app.Refuse(new BeginDownload(id, Profile, "a.pdf", Epoch, false)));
        Assert.Equal(new InvalidDownloadText(DownloadTextField.Message), app.Refuse(new CancelDownload(id, "")));
        Assert.Equal(new InvalidDownloadProgress(), app.Refuse(new RecordDownloadTransfer(id, DownloadTelemetry.Empty, double.NaN)));
        var waiting = Updated(app.Send(new AwaitDownloadApproval(id)));
        Assert.Equal((0, DownloadPhase.AwaitingApproval, "a.pdf"), (waiting.Position, waiting.Download.Phase, waiting.Download.Filename));

        Assert.Equal([id], Assert.IsType<DownloadsRemoved>(Assert.Single(app.Send(new RemoveDownload(id)))).DownloadIds);
        Assert.Empty(app.Send(new RemoveDownload(id)));
    }

    [Fact]
    public void QueriesAnswerThroughTheBoundaryWithoutChangingRecords() {
        using var app = new AppClient();
        var verdict = app.Ask(new DownloadRisk(new("photo.jpg\u202Egpj.command", "photo.jpggpj.command",
            "application/octet-stream", true, false, null), true), ContractCodec.ReadDownloadRiskVerdict);
        Assert.Equal([DownloadRiskReason.ExecutableOrInstaller, DownloadRiskReason.DeceptiveFilename], verdict.Assessment.Reasons);
        Assert.True(verdict.RequiresConfirmation);

        var first = app.Ask(new DownloadProgress(null, 0, 10_000, 0, false, 0), ContractCodec.ReadDownloadProgressReading);
        var second = app.Ask(new DownloadProgress(first.Estimator, 1_000, 10_000, 0.1, false, 1),
            ContractCodec.ReadDownloadProgressReading);
        Assert.Equal(1_000, second.Telemetry.BytesPerSecond!.Value, 3);
        Assert.Equal(0.1, second.Progress, 3);
        Assert.Equal(new InvalidDownloadSample(), app.Refuse(new DownloadProgress(first.Estimator, 1, 1, 0, false, double.NaN)));
        Assert.Empty(app.Send(new AcknowledgeDownloads(Profile)));
    }

    [Fact]
    public void ExpiryRemovesOnlyFinalRecordsOlderThanTheirProfilesShortestRetention() {
        using var app = new AppClient();
        Guid expired = Guid.NewGuid(), boundary = Guid.NewGuid(), live = Guid.NewGuid(), kept = Guid.NewGuid();
        var now = Epoch.AddSeconds(1_000);
        app.Send(new BeginDownload(expired, Profile, "old.pdf", now.AddSeconds(-61), false));
        app.Send(new FinishDownload(expired, 10));
        app.Send(new BeginDownload(boundary, Profile, "edge.pdf", now.AddSeconds(-60), false));
        app.Send(new FinishDownload(boundary, 10));
        app.Send(new BeginDownload(live, Profile, "live.pdf", now.AddSeconds(-500), false));
        app.Send(new BeginDownload(kept, Other, "other.pdf", Epoch, false));
        app.Send(new FinishDownload(kept, 10));

        var removed = app.Send(new ExpireDownloads(now, [new(Profile, TimeSpan.FromMinutes(5)), new(Profile, TimeSpan.FromSeconds(60)),
            new(Other, null)]));

        Assert.Equal([expired], Assert.IsType<DownloadsRemoved>(Assert.Single(removed)).DownloadIds);
        Assert.Empty(app.Send(new ExpireDownloads(now, [new(Profile, TimeSpan.FromSeconds(60))])));
        Assert.Equal(new InvalidRetentionLifetime(), app.Refuse(new ExpireDownloads(now, [new(Profile, TimeSpan.FromSeconds(-1))])));
        Assert.Equal([live, boundary], Assert.IsType<DownloadsRemoved>(Assert.Single(app.Send(new RemoveProfileDownloads(Profile))))
            .DownloadIds);
    }
}
