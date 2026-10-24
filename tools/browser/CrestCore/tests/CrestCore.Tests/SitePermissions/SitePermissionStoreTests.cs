using System.Globalization;
using System.Text;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Site permission choices are device state: the device store keeps the
/// persistent session's choices beside the session, carried once from the
/// document an installed release kept, and every other Space's choices live
/// in memory.
public sealed partial class BrowserContractsTests {
    private static readonly SiteOrigin Conference = new("https", "meet.example", 443);

    /// One stored row of `device_site_permission`, spelled exactly as the store holds it.
    private sealed record StoredPermissionRow(string Id, string Space, string Scheme, string Host, long Port, string Permission,
        string? Detail, string Decision, long ModifiedAtBits);

    private static List<StoredPermissionRow> StoredPermissionRows(string file) {
        Assert.Equal(Sqlite.Ok, Sqlite.sqlite3_open_v2(file, out var connection, Sqlite.OpenReadOnly, null));
        try {
            Assert.Equal(Sqlite.Ok, Sqlite.sqlite3_prepare_v2(connection, "SELECT id, space, scheme, host, port, permission, detail, "
                + "decision, modified_at FROM device_site_permission ORDER BY position", -1, out var statement, 0));
            var rows = new List<StoredPermissionRow>();
            while (Sqlite.sqlite3_step(statement) == Sqlite.Row)
                rows.Add(new(Sqlite.ColumnText(statement, 0), Sqlite.ColumnText(statement, 1), Sqlite.ColumnText(statement, 2),
                    Sqlite.ColumnText(statement, 3), Sqlite.sqlite3_column_int64(statement, 4), Sqlite.ColumnText(statement, 5),
                    Sqlite.ColumnIsNull(statement, 6) ? null : Sqlite.ColumnText(statement, 6), Sqlite.ColumnText(statement, 7),
                    BitConverter.DoubleToInt64Bits(Sqlite.sqlite3_column_double(statement, 8))));
            Sqlite.sqlite3_finalize(statement);
            return rows;
        } finally {
            Sqlite.sqlite3_close_v2(connection);
        }
    }

    /// One entry of the document an installed release saved, in the order and
    /// spelling its encoder wrote: origin, permission, id, the optional detail,
    /// the Space wrapped as `rawValue`, decision, then the time as the double
    /// it printed.
    private static string LegacyPermission(Guid id, Guid space, string host, string permission, string decision, string modifiedAt,
        string? detail = null) =>
        "{\"origin\":{\"scheme\":\"https\",\"host\":\"" + host + "\",\"port\":443},\"permission\":\"" + permission
        + "\",\"id\":\"" + id.ToString().ToUpperInvariant() + "\","
        + (detail is null ? "" : "\"detail\":\"" + detail + "\",")
        + "\"spaceID\":{\"rawValue\":\"" + space.ToString().ToUpperInvariant() + "\"},\"decision\":\"" + decision
        + "\",\"modifiedAt\":" + modifiedAt + "}";

    private static SitePermissionDecision Decided(CrestApp app, Guid space, SitePermission permission, SiteOrigin? origin = null,
        string? detail = null) => app.Query(new SiteDecision(space, origin ?? Conference, permission, detail)).Decision;

    [Fact]
    public void TheSitePermissionsAnInstalledReleaseKeptAreAdoptedOnceExactlyAsStored() {
        using var directory = new StorageDirectory();
        Guid first, second, departed = Guid.NewGuid();
        var kept = new[] {
            (Id: Guid.NewGuid(), Host: "meet.example", Permission: "camera", Decision: "grantPersistently", At: "808529885.001641",
                Detail: (string?)null, Space: 0),
            (Id: Guid.NewGuid(), Host: "mail.example", Permission: "externalApplications", Decision: "denyPersistently",
                At: "780000000.1234567", Detail: (string?)"mailto", Space: 0),
            (Id: Guid.NewGuid(), Host: "news.example", Permission: "notifications", Decision: "grantPersistently", At: "750000000",
                Detail: (string?)null, Space: 1),
            // A choice for a Space this device no longer has is carried as it was.
            (Id: Guid.NewGuid(), Host: "old.example", Permission: "popups", Decision: "denyPersistently", At: "6.5e8",
                Detail: (string?)null, Space: 2),
        };
        {
            var (app, _, spaces) = DeviceApp(directory);
            using var disposal = app;
            (first, second) = (SpaceId(spaces[0]!), SpaceId(spaces[1]!));
            Guid[] owners = [first, second, departed];
            var entries = kept.Select(entry => LegacyPermission(entry.Id, owners[entry.Space], entry.Host, entry.Permission, entry.Decision,
                entry.At, entry.Detail)).ToList();
            // A repeat of the first choice, an answer for this session only, an
            // entry that cannot be read and a capability this build does not
            // know are left out.
            entries.Add(LegacyPermission(Guid.NewGuid(), first, "meet.example", "camera", "denyPersistently", "1"));
            entries.Add(LegacyPermission(Guid.NewGuid(), first, "meet.example", "microphone", "grantForSession", "1"));
            entries.Add("""{"origin":{"scheme":"https","host":"x.example","port":443},"permission":"camera","id":"not an id"}""");
            entries.Add(LegacyPermission(Guid.NewGuid(), first, "meet.example", "midi", "grantPersistently", "1"));
            var document = Encoding.UTF8.GetBytes("[" + string.Join(",", entries) + "]");

            var published = app.Send(new AdoptSitePermissions(document)).OfType<SitePermissionsChanged>().ToDictionary(change => change.SpaceId);
            Assert.Equal(new[] { first, second, departed }.Order(), published.Keys.Order());
            Assert.Equal(["https://mail.example", "https://meet.example"], published[first].Records.Select(record => record.SiteName));
            Assert.Empty(published[first].Touched);
            Assert.Equal(SitePermissionDecision.GrantPersistently, Decided(app, first, SitePermission.Camera));
            Assert.Equal(SitePermissionDecision.DenyPersistently,
                Decided(app, first, SitePermission.ExternalApplications, new("https", "mail.example", 443), "mailto"));

            // A later adoption carries nothing more and publishes what the store holds.
            var again = app.Send(new AdoptSitePermissions(Encoding.UTF8.GetBytes(
                "[" + LegacyPermission(Guid.NewGuid(), second, "late.example", "camera", "grantPersistently", "1") + "]")));
            Assert.Equal(published[second].Records, Assert.Single(again.OfType<SitePermissionsChanged>(), change => change.SpaceId == second).Records);
        }

        // Every value is stored exactly as the document spelled it.
        Guid[] spacesByIndex = [first, second, departed];
        Assert.Equal(kept.Select(entry => new StoredPermissionRow(entry.Id.ToString().ToUpperInvariant(),
                spacesByIndex[entry.Space].ToString().ToUpperInvariant(), "https", entry.Host, 443, entry.Permission, entry.Detail,
                entry.Decision, BitConverter.DoubleToInt64Bits(double.Parse(entry.At, CultureInfo.InvariantCulture)))),
            StoredPermissionRows(directory.File));

        var (relaunched, _, _) = DeviceApp(directory);
        using var relaunchedDisposal = relaunched;
        Assert.Equal(SitePermissionDecision.GrantPersistently, Decided(relaunched, second, SitePermission.Notifications,
            new("https", "news.example", 443)));
        relaunched.Send(new AdoptSitePermissions(Encoding.UTF8.GetBytes(
            "[" + LegacyPermission(Guid.NewGuid(), second, "late.example", "camera", "grantPersistently", "1") + "]")));
        Assert.Equal(SitePermissionDecision.Ask, Decided(relaunched, second, SitePermission.Camera, new("https", "late.example", 443)));
        Assert.Equal(kept.Length, StoredPermissionRows(directory.File).Count);
    }

    [Fact]
    public void OnlyThePersistentSessionsChoicesAreKeptAndALockedSpaceNeverAnswers() {
        using var directory = new StorageDirectory();
        Guid open, guarded, privateSpace, stranger = Guid.NewGuid();
        {
            var (app, workspace, spaces) = DeviceApp(directory);
            using var disposal = app;
            var session = app.Workspace(workspace).Current;
            guarded = session.Spaces.First(space => space.Settings.AccessPolicy != SpaceAccessPolicy.Open).Id;
            open = session.Spaces.First(space => space.Settings.AccessPolicy == SpaceAccessPolicy.Open).Id;
            var privateWorkspace = TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, Seed: null)));
            privateSpace = app.Workspace(privateWorkspace).Current.Spaces.Single().Id;
            // A borrowed workspace shows its owner's Space, whose choices the store keeps.
            TestWorkspaces.Borrow(app, workspace, spaces.Single(space => SpaceId(space!) == open)!);

            IReadOnlyList<Change> Decide(Guid space, SitePermission permission, SitePermissionDecision decision) =>
                app.Send(new DecideSitePermission(space, Conference, permission, null, decision));
            var camera = Assert.Single(Assert.Single(Decide(open, SitePermission.Camera, SitePermissionDecision.GrantPersistently)
                .OfType<SitePermissionsChanged>()).Records).Id;
            Decide(open, SitePermission.Microphone, SitePermissionDecision.GrantForSession);
            Decide(open, SitePermission.Location, SitePermissionDecision.DenyPersistently);
            Decide(privateSpace, SitePermission.Camera, SitePermissionDecision.GrantPersistently);
            Decide(stranger, SitePermission.Camera, SitePermissionDecision.GrantPersistently);
            Decide(guarded, SitePermission.Popups, SitePermissionDecision.GrantPersistently);
            Assert.Equal(SitePermissionDecision.GrantForSession, Decided(app, open, SitePermission.Microphone));
            Assert.Equal(SitePermissionDecision.GrantPersistently, Decided(app, privateSpace, SitePermission.Camera));
            Assert.Equal(SitePermissionDecision.GrantPersistently, Decided(app, stranger, SitePermission.Camera));

            // A locked Space answers Ask and refuses a choice, while a reset still applies.
            app.Send(new LockSpace(guarded));
            Assert.Equal(SitePermissionDecision.Ask, Decided(app, guarded, SitePermission.Popups));
            Assert.Equal(new SpaceLocked(guarded), Assert.Throws<Rejected>(() =>
                Decide(guarded, SitePermission.Camera, SitePermissionDecision.GrantPersistently)).Rejection);
            var reset = Assert.Single(app.Send(new ResetSpacePermissions(guarded)).OfType<SitePermissionsChanged>());
            Assert.Equal(guarded, reset.SpaceId);
            Assert.Empty(reset.Records);
            Assert.Equal([new SitePermissionScope(null, null, null, RevokesAuthorization: true)], reset.Touched);
            // A Space that keeps nothing still tells its pages to withdraw, so a request waiting for an answer ends.
            Assert.Equal(reset.Touched, Assert.Single(app.Send(new ResetSpacePermissions(guarded)).OfType<SitePermissionsChanged>()).Touched);

            // Forgetting one choice revokes it; one that is gone changes nothing.
            Assert.Empty(app.Send(new ResetSitePermission(Guid.NewGuid())).OfType<SitePermissionsChanged>());
            var forgotten = Assert.Single(app.Send(new ResetSitePermission(camera)).OfType<SitePermissionsChanged>());
            Assert.Equal(open, forgotten.SpaceId);
            Assert.Equal([SitePermission.Location], forgotten.Records.Select(record => record.Permission));
            Assert.Equal([new SitePermissionScope(Conference, SitePermission.Camera, null, RevokesAuthorization: true)], forgotten.Touched);
        }

        // Only the persistent session's persistent choices reached the store.
        Assert.Equal([(open.ToString().ToUpperInvariant(), "location")],
            StoredPermissionRows(directory.File).Select(row => (row.Space, row.Permission)));
        var (relaunched, _, _) = DeviceApp(directory);
        using var relaunchedDisposal = relaunched;
        Assert.Equal(SitePermissionDecision.DenyPersistently, Decided(relaunched, open, SitePermission.Location));
        Assert.Equal(SitePermissionDecision.Ask, Decided(relaunched, open, SitePermission.Microphone));
        Assert.Equal(SitePermissionDecision.Ask, Decided(relaunched, privateSpace, SitePermission.Camera));
        Assert.Equal(SitePermissionDecision.Ask, Decided(relaunched, stranger, SitePermission.Camera));
    }

    [Fact]
    public void ANotificationShowsOnlyWhereItsSpaceAllowsTheSecureSiteAndNeverInAPrivateWindow() {
        using var directory = new StorageDirectory();
        var (app, workspace, _) = DeviceApp(directory);
        using var disposal = app;
        var space = app.Workspace(workspace).Current.Spaces.First(space => space.Settings.AccessPolicy == SpaceAccessPolicy.Open).Id;
        var privateSpace = app.Workspace(TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, Seed: null))))
            .Current.Spaces.Single().Id;
        var insecure = new SiteOrigin("http", "meet.example", 80);
        bool Shows(Guid space, SiteOrigin origin) => app.Query(new NotificationDisplayCheck(space, origin)).Shows;
        void Decide(Guid space, SiteOrigin origin, SitePermissionDecision decision) =>
            app.Send(new DecideSitePermission(space, origin, SitePermission.Notifications, null, decision));

        Assert.False(Shows(space, Conference));
        foreach (var target in new[] { space, privateSpace }) {
            Decide(target, Conference, SitePermissionDecision.GrantForSession);
            Decide(target, insecure, SitePermissionDecision.GrantForSession);
        }
        Assert.True(Shows(space, Conference));
        Assert.False(Shows(space, insecure));
        // A private window's Space keeps its own choice, which never reaches the system.
        Assert.Equal(SitePermissionDecision.GrantForSession, Decided(app, privateSpace, SitePermission.Notifications));
        Assert.False(Shows(privateSpace, Conference));

        Decide(space, Conference, SitePermissionDecision.DenyPersistently);
        Assert.False(Shows(space, Conference));
    }

    [Fact]
    public void ProfileNotificationsRequireAnAccessibleNonPrivateOwnerAndTheSourcesGrant() {
        using var directory = new StorageDirectory();
        var (app, workspace, _) = DeviceApp(directory);
        using var disposal = app;
        var space = app.Workspace(workspace).Current.Spaces.First(space => space.Settings.AccessPolicy == SpaceAccessPolicy.Open);
        var privateWorkspace = TestWorkspaces.Opened(app.Send(new OpenWorkspace(WorkspaceKind.Private, Seed: null)));
        var privateSpace = app.Workspace(privateWorkspace).Current.Spaces.Single();
        var extension = new SiteOrigin("chrome-extension", "abcdefghijklmnopabcdefghijklmnop", 0);
        bool Shows(Guid profile, SiteOrigin origin, ProfileNotificationSource source) =>
            app.Query(new ProfileNotificationDisplayCheck(profile, origin, source)).Shows;

        Assert.False(Shows(space.ProfileId, Conference, ProfileNotificationSource.ServiceWorker));
        app.Send(new DecideSitePermission(space.Id, Conference, SitePermission.Notifications, null,
            SitePermissionDecision.GrantForSession));
        Assert.True(Shows(space.ProfileId, Conference, ProfileNotificationSource.ServiceWorker));
        Assert.True(Shows(space.ProfileId, extension, ProfileNotificationSource.Extension));
        Assert.False(Shows(space.ProfileId, Conference, ProfileNotificationSource.Extension));
        Assert.False(Shows(space.ProfileId, extension, ProfileNotificationSource.ServiceWorker));
        Assert.False(Shows(Guid.NewGuid(), extension, ProfileNotificationSource.Extension));
        Assert.False(Shows(privateSpace.ProfileId, extension, ProfileNotificationSource.Extension));
        app.Send(new DecideSitePermission(privateSpace.Id, Conference, SitePermission.Notifications, null,
            SitePermissionDecision.GrantForSession));
        Assert.False(Shows(privateSpace.ProfileId, Conference, ProfileNotificationSource.ServiceWorker));

        app.Send(new SetSpaceAccess(workspace, space.Id, SpaceAccessPolicy.DeviceOwnerAuthentication));
        app.Send(new LockSpace(space.Id));
        Assert.False(Shows(space.ProfileId, Conference, ProfileNotificationSource.ServiceWorker));
        Assert.False(Shows(space.ProfileId, extension, ProfileNotificationSource.Extension));
    }

    [Fact]
    public void SitePermissionLimitsRefuseWithTheirLimit() {
        using var directory = new StorageDirectory();
        var (app, _, spaces) = DeviceApp(directory);
        using var disposal = app;
        var space = SpaceId(spaces[0]!);
        var full = Enumerable.Range(0, SitePermissionLedger.MaximumRecords)
            .Select(index => LegacyPermission(Guid.NewGuid(), space, $"site{index}.example", "camera", "grantPersistently", "1"));
        app.Send(new AdoptSitePermissions(Encoding.UTF8.GetBytes("[" + string.Join(",", full) + "]")));

        Assert.Equal(new SitePermissionLimitReached(SitePermissionLedger.MaximumRecords), Assert.Throws<Rejected>(() =>
            app.Send(new DecideSitePermission(space, Conference, SitePermission.Microphone, null, SitePermissionDecision.GrantPersistently)))
            .Rejection);
        // Changing a choice the store already holds needs no room.
        Assert.Single(app.Send(new DecideSitePermission(space, new("https", "site0.example", 443), SitePermission.Camera, null,
            SitePermissionDecision.DenyPersistently)).OfType<SitePermissionsChanged>());
        Assert.Equal(new InvalidSitePermissionDetail(SitePermissionLedger.MaximumDetailLength), Assert.Throws<Rejected>(() =>
            app.Send(new DecideSitePermission(space, Conference, SitePermission.ExternalApplications,
                new string('x', SitePermissionLedger.MaximumDetailLength + 1), SitePermissionDecision.DenyForSession))).Rejection);
        var nowhere = new SiteOrigin("https", "", 443);
        Assert.Equal(new InvalidSiteOrigin(nowhere), Assert.Throws<Rejected>(() =>
            app.Send(new DecideSitePermission(space, nowhere, SitePermission.Camera, null, SitePermissionDecision.Ask))).Rejection);
    }
}
