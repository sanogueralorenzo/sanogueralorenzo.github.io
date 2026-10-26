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

}
