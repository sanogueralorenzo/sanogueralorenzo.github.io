using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class SitePermissionLedgerTests {
    private static readonly SiteOrigin Meet = new("https", "meet.example", 443);

    private static void Set(SitePermissionLedger ledger, Guid space, SitePermission permission, SitePermissionDecision decision,
        string? detail = null, SiteOrigin? origin = null) =>
        ledger.Set(space, origin ?? Meet, permission, detail, decision, Guid.NewGuid(), 10);

    [Fact]
    public void OriginsNormalizeCaseAndDefaultWebPorts() {
        Assert.Equal(new SiteOrigin("http", "news.example", 80), new SiteOrigin("HTTP", "News.Example", 0));
        Assert.Equal(new SiteOrigin("https", "news.example", 443), new SiteOrigin("HTTPS", "News.Example", -1));
        Assert.Equal(0, new SiteOrigin("custom", "Handler.Example", 0).Port);
        Assert.Equal("https://meet.example", Meet.DisplayName);
        Assert.Equal("https://meet.example:8443", new SiteOrigin("https", "meet.example", 8443).DisplayName);
        Assert.False(new SiteOrigin("https", "", 443).IsValid);
        Assert.Equal(SitePermissionDecision.Ask,
            new SitePermissionLedger().Decision(Guid.NewGuid(), new SiteOrigin("https", "", 443), SitePermission.Camera, null, false));
        Assert.Equal(new InvalidSiteOrigin(new SiteOrigin("https", "", 443)), Assert.Throws<Rejected>(() => new SitePermissionLedger()
            .Set(Guid.NewGuid(), new SiteOrigin("https", "", 443), SitePermission.Camera, null, SitePermissionDecision.GrantPersistently,
                Guid.NewGuid(), 1)).Rejection);
    }

    [Fact]
    public void DecisionsAreScopedToSpaceOriginAndCapability() {
        var ledger = new SitePermissionLedger();
        Guid work = Guid.NewGuid(), personal = Guid.NewGuid();
        Set(ledger, work, SitePermission.Camera, SitePermissionDecision.GrantForSession);

        Assert.Equal(SitePermissionDecision.GrantForSession, ledger.Decision(work, Meet, SitePermission.Camera, null, false));
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision(work, Meet, SitePermission.Microphone, null, false));
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision(work, new("https", "meet.example", 8443), SitePermission.Camera, null, false));
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision(personal, Meet, SitePermission.Camera, null, false));
    }

    [Fact]
    public void SessionChoicesOverrideWithoutReplacingOrPersisting() {
        var ledger = new SitePermissionLedger();
        var space = Guid.NewGuid();
        Set(ledger, space, SitePermission.Camera, SitePermissionDecision.GrantPersistently);
        var outcome = ledger.Set(space, Meet, SitePermission.Camera, null, SitePermissionDecision.DenyForSession, Guid.NewGuid(), 20);

        Assert.False(outcome.PersistenceChanged);
        Assert.True(Assert.Single(outcome.Changes).Scope.RevokesAuthorization);
        Assert.Equal(SitePermissionDecision.DenyForSession, ledger.Decision(space, Meet, SitePermission.Camera, null, false));
        Assert.Equal(SitePermissionDecision.GrantPersistently, Assert.Single(ledger.PersistentRecords).Decision);

        var restarted = new SitePermissionLedger();
        restarted.Restore(ledger.PersistentRecords);
        Assert.Equal(SitePermissionDecision.GrantPersistently, restarted.Decision(space, Meet, SitePermission.Camera, null, false));

        // Restoring the kept records leaves the session's own choices in place.
        ledger.Restore(ledger.PersistentRecords.ToArray());
        Assert.Equal(SitePermissionDecision.DenyForSession, ledger.Decision(space, Meet, SitePermission.Camera, null, false));
    }

    [Fact]
    public void ChangingASavedChoiceKeepsItsIdentityAndAskRemovesIt() {
        var ledger = new SitePermissionLedger();
        var space = Guid.NewGuid();
        Set(ledger, space, SitePermission.Microphone, SitePermissionDecision.GrantPersistently);
        var original = Assert.Single(ledger.PersistentRecords).Id;

        ledger.Set(space, Meet, SitePermission.Microphone, null, SitePermissionDecision.DenyPersistently, Guid.NewGuid(), 30);
        var record = Assert.Single(ledger.PersistentRecords);
        Assert.Equal(original, record.Id);
        Assert.Equal(30, record.ModifiedAt);

        var cleared = ledger.Set(space, Meet, SitePermission.Microphone, null, SitePermissionDecision.Ask, Guid.NewGuid(), 40);
        Assert.True(cleared.PersistenceChanged);
        Assert.Empty(ledger.PersistentRecords);
    }

    [Fact]
    public void ANarrowChoiceWinsAndTheSiteWideRuleCoversTheRest() {
        var ledger = new SitePermissionLedger();
        var space = Guid.NewGuid();
        Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.DenyPersistently);
        Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.GrantPersistently, "mailto");
        Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.GrantPersistently, "tel");

        Assert.Equal(SitePermissionDecision.GrantPersistently, ledger.Decision(space, Meet, SitePermission.ExternalApplications, "mailto", false));
        Assert.Equal(SitePermissionDecision.DenyPersistently, ledger.Decision(space, Meet, SitePermission.ExternalApplications, "zoommtg", false));

        Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.Ask, "mailto");
        Assert.Equal(SitePermissionDecision.DenyPersistently, ledger.Decision(space, Meet, SitePermission.ExternalApplications, "mailto", false));
        Assert.Equal(SitePermissionDecision.GrantPersistently, ledger.Decision(space, Meet, SitePermission.ExternalApplications, "tel", false));
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision(space, Meet, SitePermission.ExternalApplications, "", false));
        Assert.Equal(new InvalidSitePermissionDetail(SitePermissionLedger.MaximumDetailLength), Assert.Throws<Rejected>(() =>
            Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.GrantPersistently, new string('x', 257))).Rejection);
    }

    [Fact]
    public void CombinedMediaCannotBypassAnIndividualBlock() {
        var ledger = new SitePermissionLedger();
        var space = Guid.NewGuid();
        Set(ledger, space, SitePermission.CameraAndMicrophone, SitePermissionDecision.GrantPersistently);
        Set(ledger, space, SitePermission.Camera, SitePermissionDecision.DenyPersistently);

        Assert.Equal(SitePermissionDecision.DenyPersistently, ledger.MediaDecision(space, Meet, SitePermission.CameraAndMicrophone, false));
        Assert.Equal(SitePermissionDecision.DenyPersistently, ledger.MediaDecision(space, Meet, SitePermission.Camera, false));
        Assert.Equal(SitePermissionDecision.GrantPersistently, ledger.MediaDecision(space, Meet, SitePermission.Microphone, false));

        Set(ledger, space, SitePermission.CameraAndMicrophone, SitePermissionDecision.Ask);
        Set(ledger, space, SitePermission.Camera, SitePermissionDecision.GrantPersistently);
        Assert.Equal(SitePermissionDecision.Ask, ledger.MediaDecision(space, Meet, SitePermission.CameraAndMicrophone, false));
        Set(ledger, space, SitePermission.Microphone, SitePermissionDecision.GrantForSession);
        Assert.Equal(SitePermissionDecision.GrantForSession, ledger.MediaDecision(space, Meet, SitePermission.CameraAndMicrophone, false));
    }

    [Fact]
    public void ALockedSpaceAnswersAskAndStillResets() {
        var ledger = new SitePermissionLedger();
        var space = Guid.NewGuid();
        Set(ledger, space, SitePermission.Camera, SitePermissionDecision.GrantPersistently);
        Set(ledger, space, SitePermission.Microphone, SitePermissionDecision.GrantForSession);

        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision(space, Meet, SitePermission.Camera, null, true));
        Assert.Equal(SitePermissionDecision.Ask, ledger.MediaDecision(space, Meet, SitePermission.Microphone, true));

        // Removal still applies, so a locked Space can be reset or deleted.
        Assert.True(ledger.ResetSpace(space).PersistenceChanged);
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision(space, Meet, SitePermission.Microphone, null, false));
        // A Space that keeps nothing still tells its pages to withdraw.
        var again = ledger.ResetSpace(space);
        Assert.False(again.PersistenceChanged);
        Assert.True(Assert.Single(again.Changes).Scope.RevokesAuthorization);
    }

    [Fact]
    public void ResettingASpaceLeavesOtherSpacesAlone() {
        var ledger = new SitePermissionLedger();
        Guid work = Guid.NewGuid(), personal = Guid.NewGuid();
        Set(ledger, work, SitePermission.Camera, SitePermissionDecision.GrantPersistently);
        Set(ledger, personal, SitePermission.Camera, SitePermissionDecision.DenyPersistently);
        Set(ledger, work, SitePermission.Microphone, SitePermissionDecision.DenyForSession);

        var change = Assert.Single(ledger.ResetSpace(work).Changes);
        Assert.Equal(work, change.Space);
        Assert.Null(change.Scope.Origin);
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision(work, Meet, SitePermission.Microphone, null, false));
        Assert.Equal(personal, Assert.Single(ledger.PersistentRecords).Space);

        var record = ledger.PersistentRecords[0];
        Assert.Equal(record.Permission, Assert.Single(ledger.ResetRecord(record.Id).Changes).Scope.Permission);
        Assert.Same(SitePermissionOutcome.Unchanged, ledger.ResetRecord(record.Id));
    }

    [Fact]
    public void RecordsListByOriginNaturallyThenCapabilityThenDetail() {
        var ledger = new SitePermissionLedger();
        var space = Guid.NewGuid();
        Set(ledger, space, SitePermission.Popups, SitePermissionDecision.GrantPersistently, origin: new("https", "b.example", 443));
        Set(ledger, space, SitePermission.Camera, SitePermissionDecision.GrantPersistently, origin: new("https", "host10.example", 443));
        Set(ledger, space, SitePermission.Camera, SitePermissionDecision.GrantPersistently, origin: new("https", "host9.example", 443));
        Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.GrantPersistently, "tel", new("https", "b.example", 443));
        Set(ledger, space, SitePermission.ExternalApplications, SitePermissionDecision.GrantPersistently, "mailto", new("https", "b.example", 443));
        Set(ledger, space, SitePermission.AutomaticDownloads, SitePermissionDecision.DenyPersistently, origin: new("https", "b.example", 443));

        var listed = ledger.Records(space).Select(record => $"{record.Origin.Host}/{record.Permission.Name}/{record.Detail}");
        Assert.Equal([
            "b.example/automaticDownloads/", "b.example/externalApplications/mailto", "b.example/externalApplications/tel",
            "b.example/popups/", "host9.example/camera/", "host10.example/camera/"
        ], listed);
    }

    [Fact]
    public void RestoreKeepsOnlyTheFirstPersistentRecordForEachChoice() {
        var space = Guid.NewGuid();
        var first = new SitePermissionRecord(Guid.NewGuid(), space, Meet, SitePermission.Camera, null, SitePermissionDecision.GrantPersistently, 1);
        var ledger = new SitePermissionLedger();
        int kept = ledger.Restore([
            first,
            first with { Id = Guid.NewGuid(), Decision = SitePermissionDecision.DenyPersistently },
            first with { Id = Guid.NewGuid(), Permission = SitePermission.Microphone, Decision = SitePermissionDecision.GrantForSession },
            first with { Id = Guid.NewGuid(), Permission = SitePermission.Location, Detail = "" },
        ]);

        Assert.Equal(1, kept);
        Assert.Equal(SitePermissionDecision.GrantPersistently, ledger.Decision(space, Meet, SitePermission.Camera, null, false));
        Assert.Equal(SitePermissionDecision.Ask, ledger.Decision(space, Meet, SitePermission.Microphone, null, false));
    }
}
