using System.Text;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The questions a page asks the person: each waits until the person answers
/// it, its engine withdraws it or its page goes; a site's permission request
/// is answered from its Space's choices when they hold one; and a credential
/// passes to the engine without being kept, published or saved.
public sealed partial class BrowserContractsTests {
    private static readonly ScriptDialogQuestion Confirmation =
        new(JavaScriptDialogKind.Confirm, "Leave?", "", "https://example.com/");

    private static PermissionQuestion LocationRequest =>
        new(SitePermission.Location, new SiteOrigin("https", "maps.example", 443), new SiteOrigin("https", "maps.example", 443));

    [Fact]
    public void AScriptDialogWaitsUntilThePersonAnswersAndTheEngineHearsTheAnswer() {
        var (app, engine, binding, page, _, _, _, _) = LivePage();
        using var disposal = app;
        var prompt = Guid.NewGuid();

        app.Report(engine, new ScriptDialogOpened(prompt, page, Confirmation));
        Assert.Equal(new ScriptDialogAsked(prompt, page, Confirmation), Assert.Single(app.Drain()));

        // Only an answer of the dialog's own kind settles it, once.
        Assert.Equal(new PromptAnswerMismatch(prompt), Refusal(app, new AnswerPermission(prompt, Grants: true, Remembers: false)));
        Assert.Equal([new PromptSettled(prompt)], app.Send(new AnswerScriptDialog(prompt, Accepted: true, Text: null)));
        Assert.Equal(new SettleScriptDialog(prompt, Accepted: true, Text: null), binding.Commands[^1]);
        Assert.Equal(new UnknownPrompt(prompt), Refusal(app, new AnswerScriptDialog(prompt, Accepted: false, Text: null)));
    }

    [Fact]
    public void ARememberedPermissionBecomesTheSpacesChoiceAndAnswersLaterRequestsWithoutAsking() {
        var (app, engine, binding, page, _, _, space, _) = LivePage();
        using var disposal = app;
        var first = Guid.NewGuid();
        app.Report(engine, new PermissionRequested(first, page, LocationRequest));
        Assert.Equal(new PermissionAsked(first, page, LocationRequest), Assert.Single(app.Drain()));

        var answered = app.Send(new AnswerPermission(first, Grants: true, Remembers: true));
        Assert.Contains(answered, change => change is SitePermissionsChanged changed && changed.SpaceId == space);
        Assert.Equal(new PromptSettled(first), answered[^1]);
        Assert.Equal(new SettlePermission(first, Grants: true, Remembers: true), binding.Commands[^1]);

        // The site asks again: the Space's choice answers, and nobody is asked.
        var second = Guid.NewGuid();
        app.Report(engine, new PermissionRequested(second, page, LocationRequest));
        Assert.Empty(app.Drain());
        Assert.Equal(new SettlePermission(second, Grants: true, Remembers: true), binding.Commands[^1]);
    }

    [Fact]
    public void ACaptureRequestIsAnsweredFromEitherDevicesBlockOrACombinedGrantWithoutAsking() {
        var (app, engine, binding, page, _, _, space, _) = LivePage();
        using var disposal = app;
        var blocked = new SiteOrigin("https", "blocked.example", 443);
        var granted = new SiteOrigin("https", "granted.example", 443);
        app.Send(new DecideSitePermission(space, blocked, SitePermission.Camera, null, SitePermissionDecision.DenyPersistently));
        app.Send(new DecideSitePermission(space, granted, SitePermission.CameraAndMicrophone, null,
            SitePermissionDecision.GrantPersistently));
        app.Drain();

        // A block on the camera refuses a request for both devices.
        var both = Guid.NewGuid();
        app.Report(engine, new PermissionRequested(both, page, new(SitePermission.CameraAndMicrophone, blocked, blocked)));
        Assert.Empty(app.Drain());
        Assert.Equal(new SettlePermission(both, Grants: false, Remembers: true), binding.Commands[^1]);

        // A grant for both answers a request for the microphone alone.
        var microphone = Guid.NewGuid();
        app.Report(engine, new PermissionRequested(microphone, page, new(SitePermission.Microphone, granted, granted)));
        Assert.Empty(app.Drain());
        Assert.Equal(new SettlePermission(microphone, Grants: true, Remembers: true), binding.Commands[^1]);
    }

    [Fact]
    public void ScreenSharingGoesOnToTheSystemsPickerUnlessBlockedAndIsNeverAllowedAhead() {
        var (app, engine, binding, page, _, _, space, _) = LivePage();
        using var disposal = app;
        var origin = new SiteOrigin("https", "meet.example", 443);
        var sharing = new PermissionQuestion(SitePermission.ScreenSharing, origin, origin);

        // Ask lets the request through to the system's own question, and Crest asks nobody.
        var first = Guid.NewGuid();
        app.Report(engine, new PermissionRequested(first, page, sharing));
        Assert.Empty(app.Drain());
        Assert.Equal(new SettlePermission(first, Grants: true, Remembers: false), binding.Commands[^1]);

        // Nothing allows a site ahead of that question; a block refuses it.
        Assert.Equal(new InvalidSitePermissionGrant(SitePermission.ScreenSharing),
            Refusal(app, new DecideSitePermission(space, origin, SitePermission.ScreenSharing, null,
                SitePermissionDecision.GrantPersistently)));
        app.Send(new DecideSitePermission(space, origin, SitePermission.ScreenSharing, null, SitePermissionDecision.DenyPersistently));
        var second = Guid.NewGuid();
        app.Report(engine, new PermissionRequested(second, page, sharing));
        Assert.Empty(app.Drain());
        Assert.Equal(new SettlePermission(second, Grants: false, Remembers: true), binding.Commands[^1]);
    }

    [Fact]
    public void ABlockTheSpaceTakesWhileAPermissionQuestionWaitsOutranksThePersonsAnswer() {
        var (app, engine, binding, page, _, _, space, _) = LivePage();
        using var disposal = app;
        var origin = new SiteOrigin("https", "media.example", 443);
        var request = Guid.NewGuid();
        app.Report(engine, new PermissionRequested(request, page, new(SitePermission.Camera, origin, origin)));
        app.Drain();

        app.Send(new DecideSitePermission(space, origin, SitePermission.Camera, null, SitePermissionDecision.DenyPersistently));
        Assert.Equal([new PromptSettled(request)], app.Send(new AnswerPermission(request, Grants: true, Remembers: true)));
        Assert.Equal(new SettlePermission(request, Grants: false, Remembers: true), binding.Commands[^1]);
        Assert.Equal(SitePermissionDecision.DenyPersistently,
            app.Query(new CaptureDecision(space, origin, SitePermission.Camera)).Decision);
    }

    [Fact]
    public void AQuestionNoHostedPageAsksIsDeclinedAndAPromptGoesWhenWithdrawnOrWithItsPage() {
        var (app, engine, binding, page, _, _, _, _) = LivePage();
        using var disposal = app;

        // A page the core does not host is answered as declined, and nobody is asked.
        var stray = Guid.NewGuid();
        app.Report(engine, new AuthenticationChallenged(stray, Guid.NewGuid(),
            new("https://example.com/", "example.com", 443, "Realm", AuthenticationScheme.Basic, IsProxy: false, PreviousFailures: 0)));
        Assert.Empty(app.Drain());
        Assert.Equal(new SettleAuthentication(stray, Credential: null), binding.Commands[^1]);

        // The engine withdraws one; another goes with its page.
        var withdrawn = Guid.NewGuid();
        var orphaned = Guid.NewGuid();
        app.Report(engine, new ScriptDialogOpened(withdrawn, page, Confirmation));
        app.Report(engine, new PermissionRequested(orphaned, page, LocationRequest));
        app.Drain();
        app.Report(engine, new PromptWithdrawn(withdrawn));
        Assert.Equal([new PromptSettled(withdrawn)], app.Drain());
        Assert.Contains(new PromptSettled(orphaned), app.Send(new ReleasePage(page, KeepsState: false)));
        Assert.DoesNotContain(binding.Commands, command => command is SettlePermission settled && settled.PromptId == orphaned);
    }

    [Fact]
    public void ACredentialPassesToTheEngineAndIsNeverKeptPublishedOrSaved() {
        const string secret = "correct-horse-7f3a9c";
        using var directory = new StorageDirectory();
        var fixture = SavedSession();
        var published = new List<Change>();
        var binding = new RecordingEngine();
        using (var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop))) {
            published.AddRange(app.Send(Adoption(fixture.Document["session"]!.AsObject())));
            var (workspace, opened) = TestWorkspaces.OpenStored(app);
            published.AddRange(opened);
            var engine = app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, IsDefault: true),
                binding.Run);
            var (window, page, prompt) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
            published.AddRange(app.Send(new OpenWindow(window, workspace, Saved: true, null, null, [], RestoresTabs: true)));
            published.AddRange(app.Send(new OpenPage(page, workspace, fixture.Space, fixture.Tab, window)));
            app.Report(engine, new PageCreated(page));
            app.Report(engine, new AuthenticationChallenged(prompt, page,
                new("https://intranet.example/", "intranet.example", 443, "Staff", AuthenticationScheme.Digest, IsProxy: false,
                    PreviousFailures: 1)));
            published.AddRange(app.Drain());

            var credential = new AuthenticationCredential("paul", secret);
            published.AddRange(app.Send(new AnswerAuthentication(prompt, credential)));
            Assert.Equal(new SettleAuthentication(prompt, credential), binding.Commands[^1]);
            Assert.DoesNotContain(secret, binding.Commands[^1].ToString());
            published.AddRange(app.Drain());
        }
        // Closing the core saved whatever was still pending.

        // Nothing published carries it, and nothing the core saved holds it in any encoding.
        Assert.DoesNotContain(published, change => change.ToString().Contains(secret, StringComparison.Ordinal));
        foreach (var file in Directory.EnumerateFiles(directory.Path, "*", SearchOption.AllDirectories)) {
            var bytes = File.ReadAllBytes(file);
            foreach (var encoding in new Encoding[] { Encoding.UTF8, Encoding.Unicode, Encoding.BigEndianUnicode })
                Assert.True(bytes.AsSpan().IndexOf(encoding.GetBytes(secret)) < 0, $"{Path.GetFileName(file)} holds the credential.");
        }
    }
}
