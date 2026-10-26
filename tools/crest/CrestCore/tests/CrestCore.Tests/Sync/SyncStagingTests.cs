using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    /// A persistent session that syncs, after its launch stage.
    private static (NativeSessionAuthority Session, NativeSyncAuthority Sync) Syncing(JsonNode session) {
        var owner = TestWorkspaces.Session(session);
        return (owner, Syncing(owner));
    }

    /// A sync component `owner` stages into, with the launch stage run.
    private static NativeSyncAuthority Syncing(NativeSessionAuthority owner) {
        var sync = new NativeSyncAuthority(NativeSyncJournal.Fresh(Guid.NewGuid()));
        owner.AttachSync(sync);
        sync.Flush();
        return sync;
    }

    /// Renames `tab` in the session's first Space through the session's own
    /// handler, where a device routes the intent.
    private static void Rename(NativeSessionAuthority owner, JsonNode session, Guid tab, string title) =>
        owner.Handle(new RenameTab(Guid.Empty, SpaceId(session["spaces"]![0]!), tab, title), DateTimeOffset.UtcNow, new TestIds());

    [Fact]
    public void ARecordAnEarlierEditOfABurstRemovedIsDeletedForThatEditsReason() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        session.Remove("disposableSeedMarker");
        using var device = new TestDevice(session);
        var (owner, sync) = (device.Authority, Syncing(device.Authority));
        var folder = Guid.NewGuid();
        device.Send(new CreateFolder(device.Workspace, fixture.Space, folder, TabPlacement.Saved, null, "Doomed",
            FolderState.DefaultColor, "folder", [], LeavesSplits: false));
        sync.Flush();
        JsonNode FolderRecord() => JsonNode.Parse(sync.Snapshot.Read())!["records"]!.AsArray().Single(record =>
            record!["id"]!["kind"]!.GetValue<string>() == "folder" && Guid.Parse(record["id"]!["value"]!.GetValue<string>()) == folder)!;
        Assert.NotNull(FolderRecord()["payload"]);

        // The rename is the newest edit, but it did not remove the folder.
        device.Send(new DeleteFolder(device.Workspace, fixture.Space, folder));
        Rename(owner, session, fixture.Tab, "Renamed after the deletion");
        sync.Flush();

        Assert.Equal("explicitDelete", FolderRecord()["tombstone"]!["reason"]!.GetValue<string>());
    }

    [Fact]
    public void ADisposableSeedSessionNeverStages() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        Assert.NotNull(session["disposableSeedMarker"]);
        var (owner, sync) = Syncing(session);

        Rename(owner, session, fixture.Tab, "Seeded edit");
        sync.Flush();

        Assert.Empty(JsonNode.Parse(sync.Snapshot.Read())!["records"]!.AsArray());
    }
}
