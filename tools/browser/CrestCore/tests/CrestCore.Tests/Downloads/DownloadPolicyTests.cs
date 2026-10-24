using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class DownloadPolicyTests {
    private static DownloadRiskAssessment Assess(string filename, string? mime, bool extensionRunsCode = false,
        bool mimeRunsCode = false, bool? related = null, string? sanitized = null) =>
        DownloadRiskAssessment.Of(new(filename, sanitized ?? filename, mime, extensionRunsCode, mimeRunsCode, related));

    [Fact]
    public void OrdinaryDocumentsCarryNoRisk() {
        var assessment = Assess("report.pdf", "application/pdf", related: true);
        Assert.Empty(assessment.Reasons);
        Assert.False(assessment.RequiresConfirmation(isUserInitiated: false));
    }

    [Theory]
    [InlineData("update.pkg")]
    [InlineData("tool.command")]
    [InlineData("setup.EXE")]
    [InlineData("profile.mobileconfig")]
    [InlineData("script.PS1")]
    public void InstallerAndScriptExtensionsAreExecutableEvenWithoutPlatformTypes(string filename) {
        var assessment = Assess(filename, "application/octet-stream");
        Assert.Equal([DownloadRiskReason.ExecutableOrInstaller], assessment.Reasons);
        Assert.True(assessment.RequiresConfirmation(isUserInitiated: false));
    }

    [Fact]
    public void PlatformTypeFactsAndDangerousMimeTypesAlsoMarkExecutables() {
        Assert.Equal([DownloadRiskReason.ExecutableOrInstaller], Assess("tool.py", "text/plain", extensionRunsCode: true).Reasons);
        Assert.Equal([DownloadRiskReason.ExecutableOrInstaller], Assess("blob", "APPLICATION/X-MSDOWNLOAD").Reasons);
        Assert.Empty(Assess("archive.", null).Reasons);
    }

    [Fact]
    public void UserInitiatedInstallersRelyOnThePlatformProtection() {
        var assessment = Assess("Crest.dmg", "application/x-apple-diskimage", true, true, true);
        Assert.Equal([DownloadRiskReason.ExecutableOrInstaller], assessment.Reasons);
        Assert.False(assessment.RequiresConfirmation(isUserInitiated: true));
        Assert.True(assessment.RequiresConfirmation(isUserInitiated: false));
    }

    [Theory]
    [InlineData("photo.jpg\u202Egpj.command")]
    [InlineData("invoice\u200B.pdf")]
    [InlineData("\uFEFFnotes.txt")]
    [InlineData("list\u2067.txt")]
    public void DirectionChangingOrInvisibleCharactersAreDeceptiveWhateverTheActivation(string filename) {
        var assessment = Assess(filename, "application/octet-stream", sanitized: "renamed.txt");
        Assert.Contains(DownloadRiskReason.DeceptiveFilename, assessment.Reasons);
        Assert.Equal("renamed.txt", assessment.SanitizedFilename);
        Assert.True(assessment.RequiresConfirmation(isUserInitiated: true));
    }

    [Fact]
    public void ADangerousTypeThatDisagreesWithItsFilenameIsAMismatch() {
        var mismatch = Assess("holiday.jpg", "application/x-mach-binary", mimeRunsCode: true, related: false);
        Assert.Equal([DownloadRiskReason.ExecutableOrInstaller, DownloadRiskReason.DangerousTypeMismatch], mismatch.Reasons);
        Assert.True(mismatch.RequiresConfirmation(isUserInitiated: true));
        Assert.DoesNotContain(DownloadRiskReason.DangerousTypeMismatch,
            Assess("holiday.jpg", "application/x-mach-binary", mimeRunsCode: true, related: null).Reasons);
        Assert.Empty(Assess("holiday.jpg", "image/png", related: false).Reasons);
    }

    [Fact]
    public void UserInitiatedDownloadsAndApprovedRetriesBypassSavedDenials() {
        Assert.Equal(AutomaticDownloadAction.Allow,
            new AutomaticDownloadCheck(true, false, SitePermissionDecision.DenyPersistently, true).Verdict.Action);
        var retry = new AutomaticDownloadCheck(false, true, SitePermissionDecision.DenyPersistently, true).Verdict;
        Assert.Equal(new AutomaticDownloadVerdict(AutomaticDownloadAction.Allow, true), retry);
    }

    [Theory]
    [InlineData("grantForSession", "allow")]
    [InlineData("grantPersistently", "allow")]
    [InlineData("denyForSession", "deny")]
    [InlineData("denyPersistently", "deny")]
    public void SavedDecisionsAnswerAutomaticDownloadsWithoutThrottling(string name, string expected) {
        var decision = SitePermissionDecision.Named(name)!;
        var verdict = new AutomaticDownloadCheck(false, false, decision, true).Verdict;
        Assert.Equal(expected, verdict.Action.Name);
        Assert.Equal(new AutomaticDownloadVerdict(AutomaticDownloadAction.Named(expected)!, false),
            new AutomaticDownloadCheck(false, false, decision, false).Verdict);
    }

    [Fact]
    public void TheFirstAutomaticDownloadIsAllowedAndAUserActionResetsTheAllowance() {
        var first = new AutomaticDownloadCheck(false, false, SitePermissionDecision.Ask, false).Verdict;
        Assert.Equal(new AutomaticDownloadVerdict(AutomaticDownloadAction.Allow, true), first);
        var second = new AutomaticDownloadCheck(false, false, SitePermissionDecision.Ask, first.HasAllowedAutomaticDownload).Verdict;
        Assert.Equal(new AutomaticDownloadVerdict(AutomaticDownloadAction.RequestPermission, true), second);
        var gesture = new AutomaticDownloadCheck(true, false, SitePermissionDecision.Ask, second.HasAllowedAutomaticDownload).Verdict;
        Assert.Equal(new AutomaticDownloadVerdict(AutomaticDownloadAction.Allow, false), gesture);
        Assert.Equal(AutomaticDownloadAction.Allow,
            new AutomaticDownloadCheck(false, false, SitePermissionDecision.Ask, gesture.HasAllowedAutomaticDownload).Verdict.Action);
    }

    [Fact]
    public void EstimatorKeepsBytesMonotonicAndSmoothsRateAndEstimate() {
        var start = DownloadTransferEstimator.Initial.Sample(0, 10_000, 0, false, 0);
        var first = start.Estimator.Sample(1_000, 10_000, 0.1, false, 1);
        var noisy = first.Estimator.Sample(3_000, 10_000, 0.3, false, 2);
        var regressed = noisy.Estimator.Sample(2_500, 10_000, 0.25, false, 3);

        Assert.Equal(1_000, first.Telemetry.BytesPerSecond!.Value, 3);
        Assert.Equal(9, first.Telemetry.EstimatedTimeRemaining!.Value, 3);
        Assert.Equal(1_250, noisy.Telemetry.BytesPerSecond!.Value, 3);
        Assert.Equal(5.6, noisy.Telemetry.EstimatedTimeRemaining!.Value, 3);
        Assert.Equal(3_000, regressed.Telemetry.BytesReceived);
        Assert.Equal(0.3, regressed.Progress, 3);
    }

    [Fact]
    public void EstimatorWaitsForAUsefulIntervalAndPausingClearsTheRate() {
        var start = DownloadTransferEstimator.Initial.Sample(0, 1_000, 0, false, 0);
        var early = start.Estimator.Sample(100, 1_000, 0.1, false, 0.1);
        Assert.Null(early.Telemetry.BytesPerSecond);
        var paused = early.Estimator.Sample(200, 1_000, 0.2, true, 1);
        Assert.True(paused.Telemetry.IsPaused);
        Assert.Null(paused.Telemetry.BytesPerSecond);
        Assert.Null(paused.Telemetry.EstimatedTimeRemaining);
        var resumed = paused.Estimator.Sample(400, 1_000, 0.4, false, 2);
        Assert.Equal(200, resumed.Telemetry.BytesPerSecond!.Value, 3);
    }

    [Fact]
    public void ADisprovedTotalIsDiscardedAndUselessEstimatesAreHidden() {
        var start = DownloadTransferEstimator.Initial.Sample(0, 100, 0, false, 0);
        var disproved = start.Estimator.Sample(500, 100, 0.5, false, 1);
        Assert.Null(disproved.Telemetry.TotalBytes);
        Assert.Null(disproved.Telemetry.EstimatedTimeRemaining);
        Assert.Equal(0.5, disproved.Progress);
        var later = disproved.Estimator.Sample(600, 10_000, 0.06, false, 2);
        Assert.Null(later.Telemetry.TotalBytes);

        var slow = DownloadTransferEstimator.Initial.Sample(0, long.MaxValue / 2, 0, false, 0).Estimator;
        var glacial = slow.Sample(1, long.MaxValue / 2, 0, false, 1);
        Assert.Null(glacial.Telemetry.EstimatedTimeRemaining);
        Assert.IsType<InvalidDownloadSample>(Assert.Throws<Rejected>(() => slow.Sample(1, 1, 0, false, double.NaN)).Rejection);
    }

    [Fact]
    public void RiskFactsTheLedgerCouldNotRecordAreRefused() {
        Assert.Equal(new InvalidDownloadText(DownloadTextField.Filename),
            Assert.Throws<Rejected>(() => Assess("report.pdf", null, sanitized: "")).Rejection);
        Assert.Equal(new InvalidDownloadText(DownloadTextField.MimeType),
            Assert.Throws<Rejected>(() => Assess("report.pdf", new string('x', 256))).Rejection);
    }
}
