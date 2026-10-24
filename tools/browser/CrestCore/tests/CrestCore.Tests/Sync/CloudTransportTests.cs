using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The cloud transport's state on this device: what the device store keeps of
/// it, how the file an installed release kept is carried over once, and the
/// rules for a full pull, an account change, and this device's overwrite.
public sealed partial class BrowserContractsTests {
    private const int TransportSchema = 3;

    /// The state file an installed release wrote, with its stable keys and
    /// spellings.
    private static byte[] LegacyTransportFile(int schema = TransportSchema, string? reason = "accountChange",
        bool? requiresAccountConfirmation = null, string? resolution = "useThisDevice") {
        var file = new JsonObject {
            ["recordSchemaVersion"] = schema,
            ["requiresFullPull"] = true,
            ["engineStateSerialization"] = new JsonObject { ["data"] = "AAEC" },
            ["systemFields"] = new JsonObject {
                ["encodedRecordsByName"] = new JsonObject { ["space:A"] = "AQID", ["tab:B"] = "BAUG" },
                ["schemaVersionsByName"] = new JsonObject { ["space:A"] = 2 }
            }
        };
        if (reason is not null) file["reconciliationReason"] = reason;
        if (requiresAccountConfirmation is { } confirming) file["requiresAccountConfirmation"] = confirming;
        if (resolution is not null) file["conflictResolution"] = resolution;
        return Encoding.UTF8.GetBytes(file.ToJsonString());
    }

    private static CloudTransportState Transport(CrestApp app, CloudTransportIntent intent) =>
        Assert.Single(app.Send(intent).OfType<CloudTransportChanged>()).State;

    private static CloudRecordFields[] KeptFields(CrestApp app, params string[] names) =>
        [.. app.Query(new CloudFieldsOf(names)).Records];

    [Fact]
    public void TheInstalledReleasesStateIsAdoptedOnceWithItsStableSpellingsAndSurvivesALaunch() {
        using var directory = new StorageDirectory();
        using (var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop))) {
            Assert.False(app.Query(new CloudTransport()).IsAdopted);
            var adopted = Transport(app, new OpenCloudTransport(TransportSchema, LegacyTransportFile()));
            Assert.Equal((true, true, true, true), (adopted.IsAdopted, adopted.RequiresFullPull, adopted.AwaitsAccountDecision,
                adopted.OverwritesCloud));
            Assert.Equal("{\"data\":\"AAEC\"}", Encoding.UTF8.GetString(adopted.EngineState!));
            var fields = KeptFields(app, "space:A", "tab:B", "folder:C");
            Assert.Equal(["space:A", "tab:B"], fields.Select(kept => kept.RecordName));
            Assert.Equal([(byte)1, 2, 3], fields[0].Fields);
            Assert.Equal(2, fields[0].SchemaVersion);
            Assert.Equal([(byte)4, 5, 6], fields[1].Fields);
            Assert.Null(fields[1].SchemaVersion);

            // Adopted once: a later file is not read again.
            var later = Transport(app, new OpenCloudTransport(TransportSchema, LegacyTransportFile(reason: null, resolution: null)));
            Assert.Equal(adopted with { EngineState = later.EngineState }, later);
        }
        using var relaunched = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        var kept = relaunched.Query(new CloudTransport());
        Assert.Equal((true, true, true, true), (kept.IsAdopted, kept.RequiresFullPull, kept.AwaitsAccountDecision, kept.OverwritesCloud));
        Assert.Equal("{\"data\":\"AAEC\"}", Encoding.UTF8.GetString(kept.EngineState!));
        Assert.Equal(2, KeptFields(relaunched, "space:A", "tab:B").Length);
        // A device write after the adoption keeps its marker.
        relaunched.Send(new ChoosePeekModifier(LinkPeekModifier.Command));
        relaunched.Send(new OpenCloudTransport(TransportSchema, LegacyTransportFile(reason: null)));
        Assert.True(relaunched.Query(new CloudTransport()).AwaitsAccountDecision);
    }

    [Fact]
    public void AnOlderSchemaLeavesTheCursorAndServerFieldsBehindButKeepsTheDecisions() {
        using var directory = new StorageDirectory();
        using (var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop))) {
            var adopted = Transport(app, new OpenCloudTransport(TransportSchema, LegacyTransportFile(schema: TransportSchema - 1)));
            Assert.Equal((true, true, true, (byte[]?)null), (adopted.RequiresFullPull, adopted.AwaitsAccountDecision,
                adopted.OverwritesCloud, adopted.EngineState));
            Assert.Empty(KeptFields(app, "space:A"));

            Transport(app, new SaveCloudEngineState([7]));
            Transport(app, new RecordCloudFields([new("space:A", [8], null)], []));
        }
        using var upgraded = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        var opened = Transport(upgraded, new OpenCloudTransport(TransportSchema + 1, Legacy: null));
        Assert.Equal((true, true, true, (byte[]?)null), (opened.RequiresFullPull, opened.AwaitsAccountDecision, opened.OverwritesCloud,
            opened.EngineState));
        Assert.Empty(KeptFields(upgraded, "space:A"));
    }

    [Fact]
    public void APauseOlderBuildsKeptForARecordRaceIsDroppedButAnAccountChangeWaits() {
        foreach (var (reason, flag, awaits) in new (string?, bool?, bool)[] {
            (null, true, false), ("legacyRecordConflict", null, false), ("accountChange", null, true), (null, null, false)
        }) {
            using var app = new CrestApp();
            var adopted = Transport(app, new OpenCloudTransport(TransportSchema,
                LegacyTransportFile(reason: reason, requiresAccountConfirmation: flag)));
            Assert.Equal(awaits, adopted.AwaitsAccountDecision);
        }
    }

    [Fact]
    public void AFileThatDoesNotReadAdoptsNothing() {
        using var app = new CrestApp();
        foreach (var unreadable in new[] {
            "not json"u8.ToArray(), "{\"conflictResolution\":\"useCloud\"}"u8.ToArray(), "{\"requiresFullPull\":\"yes\"}"u8.ToArray(),
            "{\"recordSchemaVersion\":3,\"systemFields\":{}}"u8.ToArray()
        })
            Assert.IsType<LegacyCloudStateUnreadable>(Assert.Throws<Rejected>(() =>
                app.Send(new OpenCloudTransport(TransportSchema, unreadable))).Rejection);
        Assert.False(app.Query(new CloudTransport()).IsAdopted);
        Assert.True(Transport(app, new OpenCloudTransport(TransportSchema, Legacy: null)).IsAdopted);
    }

    [Fact]
    public void OnlyAnAccountChangeThatAlwaysPausesWaitsForTheFirstDecision() {
        foreach (var transition in CloudAccountTransition.All) {
            using var app = new CrestApp();
            Transport(app, new OpenCloudTransport(TransportSchema, Legacy: null));
            Assert.Equal(transition.AlwaysPauses, Transport(app, new ObserveCloudAccountChange(transition)).AwaitsAccountDecision);
            // A sign-in never ends a pause another change began.
            Transport(app, new ObserveCloudAccountChange(CloudAccountTransition.SwitchAccounts));
            Assert.True(Transport(app, new ObserveCloudAccountChange(CloudAccountTransition.SignIn)).AwaitsAccountDecision);
        }
    }

    [Fact]
    public void AResetStartsOverInOneSaveAndMayOverwriteTheCloud() {
        using var app = new CrestApp();
        Transport(app, new OpenCloudTransport(TransportSchema, LegacyTransportFile()));
        foreach (bool overwrites in new[] { true, false }) {
            var reset = Transport(app, new ResetCloudTransport(overwrites));
            Assert.Equal((false, false, overwrites, (byte[]?)null), (reset.RequiresFullPull, reset.AwaitsAccountDecision,
                reset.OverwritesCloud, reset.EngineState));
            Assert.Empty(KeptFields(app, "space:A", "tab:B"));
        }
    }

    [Fact]
    public void RemovingCrestsICloudDataForgetsTheCursorUnlessThisDeviceRestoresTheZone() {
        foreach (var loss in CloudZoneLoss.All) {
            using var app = new CrestApp();
            Transport(app, new OpenCloudTransport(TransportSchema, LegacyTransportFile()));
            var forgotten = Transport(app, new ForgetCloudZone(loss));
            Assert.Equal(loss.RestoresLocalRecords, forgotten.EngineState is not null);
            Assert.Empty(KeptFields(app, "space:A", "tab:B"));
        }
    }

    [Fact]
    public void AFailedMergeKeepsTheFullPullUntilAFullSnapshotIsTakenWithNoneFailingMeanwhile() {
        using var directory = new StorageDirectory();
        long Begin(CrestApp app) => Assert.Single(app.Send(new BeginCloudMerge()).OfType<CloudMergeBegan>()).MergeId;
        using (var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop))) {
            Transport(app, new OpenCloudTransport(TransportSchema, Legacy: null));
            long ok = Begin(app);
            Assert.True(app.Query(new CloudTransport()).RequiresFullPull);
            Assert.False(Transport(app, new FinishCloudMerge(ok, Succeeded: true, FullSnapshot: false)).RequiresFullPull);
            Assert.True(Transport(app, new FinishCloudMerge(Begin(app), Succeeded: false, FullSnapshot: false)).RequiresFullPull);
        }
        // The failure survives a launch; only a full snapshot recovers it.
        using var relaunched = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        Assert.True(relaunched.Query(new CloudTransport()).RequiresFullPull);
        Assert.True(Transport(relaunched, new FinishCloudMerge(Begin(relaunched), Succeeded: true, FullSnapshot: false)).RequiresFullPull);
        long snapshot = Begin(relaunched), overlapping = Begin(relaunched);
        Assert.True(Transport(relaunched, new FinishCloudMerge(snapshot, Succeeded: true, FullSnapshot: true)).RequiresFullPull);
        Assert.False(Transport(relaunched, new FinishCloudMerge(overlapping, Succeeded: true, FullSnapshot: false)).RequiresFullPull);
        // A snapshot a failure overtook recovers nothing.
        long overtaken = Begin(relaunched);
        Transport(relaunched, new FinishCloudMerge(Begin(relaunched), Succeeded: false, FullSnapshot: false));
        Assert.True(Transport(relaunched, new FinishCloudMerge(overtaken, Succeeded: true, FullSnapshot: true)).RequiresFullPull);
        Assert.Equal(new UnknownCloudMerge(overtaken), Assert.Throws<Rejected>(() =>
            relaunched.Send(new FinishCloudMerge(overtaken, Succeeded: true, FullSnapshot: true))).Rejection);
    }

    [Fact]
    public void ThisDevicesOverwriteLastsUntilEverythingItStagedHasUploaded() {
        using var directory = new StorageDirectory();
        var document = SavedSession().Document["session"]!.AsObject();
        document.Remove("disposableSeedMarker");
        using (var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop))) {
            var answered = app.Send(Adoption(document));
            var (_, opened) = TestWorkspaces.OpenStored(app);
            _ = DrainLaunch(app, [.. answered, .. opened]);
            Transport(app, new OpenCloudTransport(TransportSchema, Legacy: null));
            Transport(app, new ResetCloudTransport(OverwritesCloud: true));
            Assert.True(Transport(app, new SettleCloudOverwrite()).OverwritesCloud);
        }
        using var relaunched = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        _ = TestWorkspaces.OpenStored(relaunched);
        Assert.True(Transport(relaunched, new SettleCloudOverwrite()).OverwritesCloud);
        var pending = relaunched.Query(new PendingUploads()).Records;
        var batch = relaunched.Query(new RecordsToUpload(pending));
        relaunched.Send(new AcknowledgeUploads([.. batch.Records.Select(upload => new UploadedRecord(new(upload.Kind, upload.Id),
            upload.Version))]));
        Assert.False(Transport(relaunched, new SettleCloudOverwrite()).OverwritesCloud);
    }

    [Fact]
    public void ARestoredSessionPullsEverythingAgainAndKeepsAnAccountDecisionThatWaits() {
        using var directory = new StorageDirectory();
        string marker = directory.File + ".cloud-recovery";
        // Before the adoption, the marker is honoured as the state is adopted.
        File.WriteAllBytes(marker, []);
        using (var app = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop))) {
            var adopted = Transport(app, new OpenCloudTransport(TransportSchema, LegacyTransportFile()));
            Assert.Equal((true, true, false, (byte[]?)null), (adopted.RequiresFullPull, adopted.AwaitsAccountDecision,
                adopted.OverwritesCloud, adopted.EngineState));
            Assert.Empty(KeptFields(app, "space:A"));
            Assert.False(File.Exists(marker));
            Transport(app, new ResetCloudTransport(OverwritesCloud: true));
            Transport(app, new ObserveCloudAccountChange(CloudAccountTransition.SignOut));
            Transport(app, new SaveCloudEngineState([9]));
            Transport(app, new RecordCloudFields([new("space:A", [1], 3)], []));
        }
        // After it, the next launch starts over.
        File.WriteAllBytes(marker, []);
        using var relaunched = new CrestApp(new AppConfiguration(directory.Path, DevicePlatform.Desktop));
        var recovered = relaunched.Query(new CloudTransport());
        Assert.Equal((true, true, false, (byte[]?)null), (recovered.RequiresFullPull, recovered.AwaitsAccountDecision,
            recovered.OverwritesCloud, recovered.EngineState));
        Assert.Empty(KeptFields(relaunched, "space:A"));
        Assert.False(File.Exists(marker));
    }
}
