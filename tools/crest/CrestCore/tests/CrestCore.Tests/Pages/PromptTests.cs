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
