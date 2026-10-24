using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// An engine's downloads in the core's ledger: each belongs to its page's
/// Space, the core judges its risk before its file has a place, where its file
/// goes and keeping a file the core or the engine warned about are prompts, the
/// person's row actions reach the engine, and a record's name never carries
/// characters that disguise the file.
public sealed partial class BrowserContractsTests {
    private static EngineDownload Transfer(Guid profile, Guid? page, EngineDownloadState state = EngineDownloadState.Preparing,
        long received = 0, long total = 100, EngineDownloadWarning? warning = null, string token = "",
        EngineDownloadInterruption? interruption = null, string? detail = null) =>
        new("7", profile, page, "report.pdf", Path: null, received, total, new DateTimeOffset(2026, 9, 25, 0, 0, 0, TimeSpan.Zero),
            Restored: false, Paused: false, state, warning, interruption, detail, token);

    /// The engine asking where `download`'s file goes, with the platform's
    /// facts about a file named `name` that it declares as `mime`.
    private static EngineDownloadDestinationRequested Destination(Guid prompt, EngineDownload download, string name,
        string? mime = null, bool userInitiated = true) =>
        new(prompt, download, name, ForcesPrompt: false,
            new DownloadRiskFacts(name, name, mime, ExtensionRunsCode: false, MimeTypeRunsCode: false, TypesRelated: null),
            userInitiated, SourceHost: "files.example");

    private static Guid ProfileOf(CrestApp app, Guid workspace, Guid space) =>
        app.Workspace(workspace).Current.Spaces.First(candidate => candidate.Id == space).ProfileId;

    [Fact]
    public void PauseAndResumeFollowTheEnginesConfirmedState() {
        var (app, engine, binding, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var profile = ProfileOf(app, workspace, space);
        var transfer = Transfer(profile, page, EngineDownloadState.Downloading, received: 50) with {
            Path = "/Downloads/report.pdf",
            CanPause = true
        };
        app.Report(engine, new EngineDownloadChanged(transfer));
        var record = app.Drain().OfType<DownloadUpdated>().Last().Download;
        Assert.True(record.CanPause);
        Assert.Empty(app.Send(new PauseDownload(record.Id)));
        Assert.Equal(new PauseEngineDownload(profile, "7"), binding.Commands[^1]);

        app.Report(engine, new EngineDownloadChanged(transfer with { Paused = true, CanPause = false, CanResume = true }));
        var paused = app.Drain().OfType<DownloadUpdated>().Last().Download;
        Assert.True(paused.Telemetry.IsPaused);
        Assert.True(paused.CanResume);
        Assert.False(paused.CanPause);
        Assert.Empty(app.Send(new ResumeDownload(record.Id)));
        Assert.Equal(new ResumeEngineDownload(profile, "7"), binding.Commands[^1]);

        app.Report(engine, new EngineDownloadChanged(transfer with { Received = 70 }));
        var resumed = app.Drain().OfType<DownloadUpdated>().Last().Download;
        Assert.False(resumed.Telemetry.IsPaused);
        Assert.False(resumed.CanResume);
        Assert.Equal(0.7, resumed.Progress);
    }

    [Fact]
    public void OnlyRequestedRecoveryCanReviveAnInterruptedDownloadAndClearingCancelsTheRequest() {
        var (app, engine, binding, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var profile = ProfileOf(app, workspace, space);
        var interrupted = Transfer(profile, page, EngineDownloadState.Failed, received: 50,
            interruption: EngineDownloadInterruption.Network) with { Path = "/Downloads/report.pdf", CanResume = true };
        app.Report(engine, new EngineDownloadChanged(interrupted));
        var record = app.Drain().OfType<DownloadUpdated>().Last().Download;
        Assert.True(record.CanResume);
        var active = interrupted with { State = EngineDownloadState.Downloading, Received = 10, CanResume = false, CanPause = true };
        app.Report(engine, new EngineDownloadChanged(active));
        Assert.Empty(app.Drain());

        app.Send(new ResumeDownload(record.Id));
        Assert.Equal(new ResumeEngineDownload(profile, "7"), binding.Commands[^1]);
        app.Report(engine, new EngineDownloadChanged(active));
        var restarted = app.Drain().OfType<DownloadUpdated>().Last().Download;
        Assert.Equal(DownloadPhase.Downloading, restarted.Phase);
        Assert.Equal(0.1, restarted.Progress);
        Assert.Null(restarted.Failure);
        Assert.Equal(record.Destination, restarted.Destination);

        app.Report(engine, new EngineDownloadChanged(interrupted));
        app.Drain();
        app.Send(new ResumeDownload(record.Id));
        app.Send(new RemoveDownload(record.Id));
        app.Report(engine, new EngineDownloadChanged(active));
        Assert.Empty(app.Drain());
        var commands = binding.Commands.Count;
        app.Send(new ResumeDownload(record.Id));
        Assert.Equal(commands, binding.Commands.Count);
    }

    [Theory]
    [InlineData(false)]
    [InlineData(true)]
    public void RecoveryCannotBypassWarningsOrSpaceAccess(bool locksSpace) {
        var (app, engine, binding, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var profile = ProfileOf(app, workspace, space);
        var transfer = Transfer(profile, page, EngineDownloadState.Failed,
            warning: locksSpace ? null : EngineDownloadWarning.PolicyBlocked,
            interruption: EngineDownloadInterruption.Network) with { CanResume = true };
        app.Report(engine, new EngineDownloadChanged(transfer));
        var record = app.Drain().OfType<DownloadUpdated>().Last().Download;
        if (locksSpace) {
            app.Send(new SetSpaceAccess(workspace, space, SpaceAccessPolicy.DeviceOwnerAuthentication));
            app.Send(new LockSpace(space));
        } else {
            Assert.False(record.CanResume);
        }
        var commands = binding.Commands.Count;
        app.Send(new ResumeDownload(record.Id));
        Assert.Equal(commands, binding.Commands.Count);
    }

    [Fact]
    public void AnEngineDownloadIsRecordedInItsPagesSpaceAndGoesWhereThePlatformAnswers() {
        var (app, engine, binding, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var profile = ProfileOf(app, workspace, space);
        var prompt = Guid.NewGuid();

        app.Report(engine, Destination(prompt, Transfer(profile, page), "../report.pdf", "application/pdf"));
        var asked = app.Drain();
        var record = Assert.IsType<DownloadUpdated>(asked[0]).Download;
        Assert.Equal((profile, "report.pdf", DownloadPhase.Preparing), (record.ProfileId, record.Filename, record.Phase));
        Assert.Equal(new DownloadDestinationAsked(prompt, record.Id, space, "report.pdf", ForcesPrompt: false), asked[^1]);

        var answered = app.Send(new AnswerDownloadDestination(prompt, "/Users/test/Downloads/report 2.pdf"));
        Assert.Equal("file:///Users/test/Downloads/report%202.pdf",
            answered.OfType<DownloadUpdated>().Single().Download.Destination);
        Assert.Contains(new PromptSettled(prompt), answered);
        Assert.Equal(new SettleDownloadDestination(prompt, "/Users/test/Downloads/report 2.pdf"), binding.Commands[^1]);

        app.Report(engine, new EngineDownloadChanged(Transfer(profile, page, EngineDownloadState.Downloading, received: 50)));
        Assert.Equal(0.5, app.Drain().OfType<DownloadUpdated>().Last().Download.Progress);
        app.Report(engine, new EngineDownloadChanged(Transfer(profile, page, EngineDownloadState.Finished, received: 100)));
        Assert.Equal(DownloadPhase.Finished, app.Drain().OfType<DownloadUpdated>().Last().Download.Phase);
    }

    /// A download that begins on a page names that page once, so its window
    /// can show it leaving, whichever engine runs it; one the engine restored
    /// from an earlier run, and one no page started, begins without it.
    [Fact]
    public void ADownloadThatBeginsOnAPageNamesItOnce() {
        var (app, engine, _, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var profile = ProfileOf(app, workspace, space);

        app.Report(engine, new EngineDownloadChanged(Transfer(profile, page)));
        var begun = app.Drain();
        var record = begun.OfType<DownloadUpdated>().First().Download;
        Assert.Equal([new DownloadStarted(record.Id, page)], begun.OfType<DownloadStarted>());
        app.Report(engine, new EngineDownloadChanged(Transfer(profile, page, EngineDownloadState.Downloading, received: 50)));
        Assert.Empty(app.Drain().OfType<DownloadStarted>());

        app.Report(engine, new EngineDownloadChanged(Transfer(profile, page) with { DownloadId = "8", Restored = true }));
        var restored = app.Drain();
        Assert.Contains(restored, change => change is DownloadUpdated);
        Assert.Empty(restored.OfType<DownloadStarted>());
        app.Report(engine, new EngineDownloadChanged(Transfer(profile, page: null) with { DownloadId = "9" }));
        var pageless = app.Drain();
        Assert.Contains(pageless, change => change is DownloadUpdated);
        Assert.Empty(pageless.OfType<DownloadStarted>());
    }

    [Fact]
    public void ADownloadNoSpaceCanHoldIsCancelledOnItsEngine() {
        var (app, engine, binding, _, _, _, _, _) = LivePage();
        using var disposal = app;
        var stranger = Guid.NewGuid();
        app.Report(engine, new EngineDownloadChanged(Transfer(stranger, page: null, EngineDownloadState.Downloading)));
        Assert.Empty(app.Drain());
        Assert.Equal(new CancelEngineDownload(stranger, "7"), binding.Commands[^1]);
    }

    [Fact]
    public void AWarnedDownloadAsksToBeKeptAndThePersonsRowActionsReachTheEngine() {
        var (app, engine, binding, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var profile = ProfileOf(app, workspace, space);

        app.Report(engine, new EngineDownloadChanged(Transfer(profile, page, EngineDownloadState.AwaitingApproval,
            warning: EngineDownloadWarning.DangerousFile, token: "danger:file")));
        var asked = app.Drain();
        var record = asked.OfType<DownloadUpdated>().Last().Download;
        Assert.Equal(DownloadPhase.AwaitingApproval, record.Phase);
        var approval = Assert.IsType<DownloadApprovalAsked>(asked[^1]);
        Assert.Equal((record.Id, "report.pdf", DownloadWarning.DangerousFile),
            (approval.DownloadId, approval.Filename, approval.Warning));
        Assert.Contains(new PromptSettled(approval.PromptId), app.Send(new AnswerDownloadApproval(approval.PromptId, Approved: true)));
        Assert.Equal(new ApproveEngineDownload(profile, "7", "danger:file"), binding.Commands[^1]);

        // The person cancels it from its row, then clears it; a late report brings nothing back.
        app.Send(new CancelDownload(record.Id, "Canceled."));
        Assert.Equal(new CancelEngineDownload(profile, "7"), binding.Commands[^1]);
        app.Send(new RemoveDownload(record.Id));
        Assert.Equal(new RemoveEngineDownload(profile, "7"), binding.Commands[^1]);
        app.Report(engine, new EngineDownloadChanged(Transfer(profile, page, EngineDownloadState.Downloading, received: 80)));
        Assert.Empty(app.Drain());
    }

    [Fact]
    public void ADownloadTheCoreJudgesDangerousIsAskedAboutBeforeItsPlaceAndDecliningCancelsIt() {
        var (app, engine, binding, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var profile = ProfileOf(app, workspace, space);
        var prompt = Guid.NewGuid();

        // An installer the site sent on its own asks first, with the core's
        // reason, its Space and only the host it came from.
        app.Report(engine, Destination(prompt, Transfer(profile, page) with { Filename = "installer.dmg" }, "installer.dmg",
            "application/x-apple-diskimage", userInitiated: false));
        var asked = app.Drain();
        var approval = Assert.IsType<DownloadApprovalAsked>(asked[^1]);
        Assert.Equal(DownloadRiskReason.ExecutableOrInstaller, Assert.Single(approval.Reasons));
        Assert.Equal((space, "installer.dmg", (DownloadWarning?)null, "files.example"),
            (approval.SpaceId, approval.Filename, approval.Warning, approval.SourceHost));
        Assert.DoesNotContain(asked, change => change is DownloadDestinationAsked);
        Assert.Equal(DownloadRiskReason.ExecutableOrInstaller,
            Assert.Single(asked.OfType<DownloadUpdated>().Last().Download.Risk!.Reasons));

        // Declining it cancels it on its engine without asking where it goes.
        var declined = app.Send(new AnswerDownloadApproval(approval.PromptId, Approved: false));
        Assert.Equal(new SettleDownloadDestination(prompt, Path: null), binding.Commands[^1]);
        Assert.DoesNotContain(declined, change => change is DownloadDestinationAsked);
        var canceled = declined.OfType<DownloadUpdated>().Last().Download;
        Assert.Equal((DownloadPhase.Canceled, "Canceled before downloading a potentially dangerous file."),
            (canceled.Phase, canceled.Message));
    }

    [Fact]
    public void AKeptDangerousDownloadIsAskedWhereItGoesAndItsEnginesWarningOfTheSameFactIsNotAskedAgain() {
        var (app, engine, binding, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var profile = ProfileOf(app, workspace, space);
        var prompt = Guid.NewGuid();
        var installer = Transfer(profile, page) with { Filename = "installer.dmg" };
        app.Report(engine, Destination(prompt, installer, "installer.dmg", userInitiated: false));
        var approval = app.Drain().OfType<DownloadApprovalAsked>().Single();

        // Keeping it asks where it goes, and only then.
        var kept = app.Send(new AnswerDownloadApproval(approval.PromptId, Approved: true));
        Assert.Equal(new DownloadDestinationAsked(prompt, approval.DownloadId, space, "installer.dmg", ForcesPrompt: false), kept[^1]);
        app.Send(new AnswerDownloadDestination(prompt, "/Users/test/Downloads/installer.dmg"));

        // The engine's warning that the file runs code is what the person
        // kept, so the core approves it without asking.
        app.Report(engine, new EngineDownloadChanged(installer with {
            State = EngineDownloadState.AwaitingApproval,
            Warning = EngineDownloadWarning.DangerousFile,
            ApprovalToken = "danger:file"
        }));
        Assert.DoesNotContain(app.Drain(), change => change is DownloadApprovalAsked);
        Assert.Equal(new ApproveEngineDownload(profile, "7", "danger:file"), binding.Commands[^1]);

        // A warning of something new asks, beside the core's reasons.
        app.Report(engine, new EngineDownloadChanged(installer with {
            State = EngineDownloadState.AwaitingApproval,
            Warning = EngineDownloadWarning.InsecureConnection,
            ApprovalToken = "insecure"
        }));
        var insecure = app.Drain().OfType<DownloadApprovalAsked>().Single();
        Assert.Equal((DownloadWarning.InsecureConnection, "files.example"),
            (insecure.Warning, insecure.SourceHost));
        Assert.Equal(DownloadRiskReason.ExecutableOrInstaller, Assert.Single(insecure.Reasons));
    }

    [Fact]
    public void ABlockedDownloadWaitsForARetryItsEngineReplaysIntoTheSameRecord() {
        var (app, engine, binding, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var profile = ProfileOf(app, workspace, space);

        app.Report(engine, new EngineDownloadChanged(Transfer(profile, page, EngineDownloadState.Blocked, token: "retry:7")));
        var blocked = app.Drain().OfType<DownloadUpdated>().Last().Download;
        Assert.Equal(DownloadPhase.BlockedAutomaticDownload, blocked.Phase);

        app.Send(new RestartDownload(blocked.Id));
        Assert.Equal(new ApproveEngineDownload(profile, "7", "retry:7"), binding.Commands[^1]);
        app.Report(engine, new EngineDownloadChanged(Transfer(profile, page, EngineDownloadState.Downloading, received: 40)));
        var resumed = app.Drain().OfType<DownloadUpdated>().Last().Download;
        Assert.Equal((blocked.Id, 0.4), (resumed.Id, resumed.Progress));

        // A blocked download the person clears leaves its engine's list.
        app.Report(engine, new EngineDownloadChanged(
            Transfer(profile, page, EngineDownloadState.Blocked, token: "retry:8") with { DownloadId = "8" }));
        var second = app.Drain().OfType<DownloadUpdated>().Last().Download;
        app.Send(new RemoveDownload(second.Id));
        Assert.Equal(new RemoveEngineDownload(profile, "8"), binding.Commands[^1]);
    }

    [Fact]
    public void AFailedDownloadRecordsWhyAsAReasonAndKeepsTheEnginesWordsAsItsMessage() {
        var (app, engine, _, page, workspace, _, space, _) = LivePage();
        using var disposal = app;
        var profile = ProfileOf(app, workspace, space);
        app.Report(engine, new EngineDownloadChanged(Transfer(profile, page, EngineDownloadState.Failed,
            interruption: EngineDownloadInterruption.NoSpace, detail: "Failed - Disk full")));
        var failed = app.Drain().OfType<DownloadUpdated>().Last().Download;
        Assert.Equal((DownloadPhase.Failed, DownloadFailure.NoSpace, "Failed - Disk full"), (failed.Phase, failed.Failure, failed.Message));

        // A download the engine blocked fails for its warning, with no words of its own.
        app.Report(engine, new EngineDownloadChanged(Transfer(profile, page, EngineDownloadState.Failed,
            warning: EngineDownloadWarning.InsecureBlocked) with { DownloadId = "8" }));
        var blocked = app.Drain().OfType<DownloadUpdated>().Last().Download;
        Assert.Equal((DownloadFailure.BlockedInsecure, (string?)null), (blocked.Failure, blocked.Message));
    }

    [Theory]
    [InlineData("folder/in‮exe.pdf", "inexe.pdf")]
    [InlineData("..\\secret​.txt..", "secret.txt")]
    [InlineData("a:b/c", "c")]
    [InlineData("  ", "download")]
    public void ADownloadsNameKeepsOnlyItsOwnSafeLastComponent(string suggested, string expected) {
        Assert.Equal(expected, DownloadFilename.Safe(suggested));
    }

    [Fact]
    public void ALongDownloadNameIsShortenedToWholeCharactersAndKeepsItsExtension() {
        var shortened = DownloadFilename.Safe(new string('é', 200) + ".pdf");
        Assert.EndsWith("é.pdf", shortened, StringComparison.Ordinal);
        Assert.True(System.Text.Encoding.UTF8.GetByteCount(shortened) <= DownloadFilename.MaximumByteCount);
    }
}
