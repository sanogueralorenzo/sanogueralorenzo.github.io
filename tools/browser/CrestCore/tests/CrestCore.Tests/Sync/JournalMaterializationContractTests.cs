using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// What a device's session becomes from its journal's records: every synced
/// value arrives in its own Space, splits and folders keep their order and
/// shape, a live tab outlasts an archive that is only an audit, and what only
/// this device keeps stays as it is.
public sealed partial class BrowserContractsTests {
    #region Actions - Tests

    [Fact]
    public void BrowsingPreferencesTravelWithTheSpaceRecord() {
        var session = OneSpaceSession();
        var preferences = JsonNode.Parse("""
            {"searchProvider":"google","selectedSearchProviderID":"custom:00000000-0000-0000-0000-0000000000D3",
             "customSearchProviders":[{"id":"00000000-0000-0000-0000-0000000000D3","name":"Kagi",
             "searchURLTemplate":"https://kagi.com/search?q=%s","suggestionURLTemplate":"https://kagi.com/api/autosuggest?q=%s"}],
             "searchSuggestionsEnabled":true,"currentTabCleanupPolicy":"after7Days","contentBlockingPolicy":"balanced",
             "dataRetention":{"history":"forever","archive":"forever","downloads":"forever"}}
            """)!;
        FirstSpace(session)["browsingPreferences"] = preferences.DeepClone();
        var journal = new JournalUnderTest(Fixed(210));
        journal.Stage(session);
        var local = session.DeepClone().AsObject();
        FirstSpace(local).Remove("browsingPreferences");

        var materialized = journal.Materialize(local);

        Assert.Equal(StoredSessionCodec.DecodeBrowsingPreferences(preferences),
            StoredSessionCodec.DecodeSpace(FirstSpace(materialized)).Settings.BrowsingPreferences);
    }

    [Fact]
    public void BrandingTravelsWithTheSpaceRecord() {
        var session = OneSpaceSession();
        var branding = JsonNode.Parse(SavedBranding)!.AsObject();
        branding["bannerPattern"] = "quartered";
        branding["themeMode"] = "gradient";
        branding["gradientAngle"] = 226.0;
        branding["crest"]!["backplate"] = "hexagon";
        branding["crest"]!["symbol"] = "bird";
        FirstSpace(session)["branding"] = branding.DeepClone();
        var journal = new JournalUnderTest(Fixed(211));

        journal.Stage(session);

        Assert.True(NativeSyncEvaluator.Equivalent(StoredSessionCodec.Encode(StoredSessionCodec.DecodeBranding(branding)),
            journal.Values(SyncRecordKind.Space)[0]["branding"]));
        var local = session.DeepClone().AsObject();
        FirstSpace(local).Remove("branding");
        Assert.Equal(StoredSessionCodec.DecodeBranding(branding),
            StoredSessionCodec.DecodeSpace(FirstSpace(journal.Materialize(local))).Settings.Branding);
    }

    [Fact]
    public void SavedTabsDisclosureTravelsWithinItsSpace() {
        var session = OneSpaceSession();
        FirstSpace(session)["isSavedTabsExpanded"] = false;
        FirstSpace(session)["savedTabsExpansionModifiedAt"] = At(350);
        var journal = new JournalUnderTest(Fixed(239));
        journal.Stage(session, at: 400);
        var local = session.DeepClone().AsObject();
        FirstSpace(local)["isSavedTabsExpanded"] = true;
        FirstSpace(local).Remove("savedTabsExpansionModifiedAt");

        var materialized = FirstSpace(journal.Materialize(local));

        var projected = journal.Values(SyncRecordKind.Space)[0];
        Assert.False(projected["isSavedTabsExpanded"]!.GetValue<bool>());
        Assert.Equal(350, Unix(projected["savedTabsExpansionModifiedAt"]), precision: 6);
        Assert.False(materialized["isSavedTabsExpanded"]!.GetValue<bool>());
        Assert.Equal(350, Unix(materialized["savedTabsExpansionModifiedAt"]), precision: 6);
    }

    [Fact]
    public void NestedFoldersTravelInSiblingOrderWithTheirLook() {
        var session = OneSpaceSession();
        var (root, child, sibling) = (Fixed(240), Fixed(241), Fixed(242));
        var childFolder = FolderOf(child, "Crest", "folder.fill", parent: root);
        childFolder["color"] = new JsonObject { ["red"] = 0.18, ["green"] = 0.42, ["blue"] = 0.72, ["alpha"] = 1.0 };
        childFolder["isCollapsed"] = true;
        childFolder["collapseModifiedAt"] = At(90);
        FirstSpace(session)["folders"] = new JsonArray(FolderOf(root, "Projects"), childFolder, FolderOf(sibling, "Reading", "books.vertical"));
        var journal = new JournalUnderTest(Fixed(243));

        journal.Stage(session);
        var folders = FirstSpace(journal.Materialize(session))["folders"]!.AsArray();

        var projected = journal.Value(SyncRecordKind.Folder, child)!;
        Assert.Equal(root, StoredSessionCodec.Identity(projected["parentID"]));
        Assert.True(NativeSyncEvaluator.Equivalent(childFolder["color"], projected["color"]));
        Assert.True(projected["isCollapsed"]!.GetValue<bool>());
        Assert.Equal(90, Unix(projected["collapseModifiedAt"]), precision: 6);
        Assert.Equal([root, child, sibling], Ids(folders));
        Assert.Equal(root, StoredSessionCodec.Identity(folders[1]!["parentID"]));
        Assert.True(NativeSyncEvaluator.Equivalent(childFolder["color"], folders[1]!["color"]));
        Assert.True(folders[1]!["isCollapsed"]!.GetValue<bool>());
    }

    [Fact]
    public void ARenameTravelsWithItsTabWithinItsSpace() {
        var session = OneSpaceSession();
        var tab = FirstSpace(session)["tabs"]![0]!;
        tab["customTitle"] = "Release Notes";
        tab["titleModifiedAt"] = At(200);
        var journal = new JournalUnderTest(Fixed(111));

        journal.Stage(session, at: 300);
        var materialized = FirstSpace(journal.Materialize(session))["tabs"]![0]!;

        var projected = journal.Value(SyncRecordKind.Tab, Fixed(102))!;
        Assert.Equal(Fixed(100), StoredSessionCodec.Identity(projected["spaceID"]));
        Assert.Equal("Release Notes", projected["customTitle"]!.GetValue<string>());
        Assert.Equal(200, Unix(projected["titleModifiedAt"]), precision: 6);
        Assert.Equal("Release Notes", materialized["customTitle"]!.GetValue<string>());
        Assert.Equal(200, Unix(materialized["titleModifiedAt"]), precision: 6);
        Assert.Equal("Example", materialized["title"]!.GetValue<string>());
    }

    [Fact]
    public void KeepingAPageLoadedTravelsWithItsTab() {
        var session = OneSpaceSession();
        FirstSpace(session)["tabs"]![0]!["keepsPageLoaded"] = true;
        var journal = new JournalUnderTest(Fixed(112));

        journal.Stage(session, at: 300);

        Assert.True(journal.Value(SyncRecordKind.Tab, Fixed(102))!["keepsPageLoaded"]!.GetValue<bool>());
        Assert.True(FirstSpace(journal.Materialize(session))["tabs"]![0]!["keepsPageLoaded"]!.GetValue<bool>());
    }

    [Fact]
    public void SplitMembershipTravelsAsOneContiguousRun() {
        var group = Fixed(1_120);
        var session = SplitSession([null, group, group, group]);
        var journal = new JournalUnderTest(Fixed(1_121));

        journal.Stage(session, at: 300);
        var tabs = FirstSpace(journal.Materialize(session))["tabs"]!.AsArray();

        var projected = journal.Values(SyncRecordKind.Tab).OrderBy(value => value["orderToken"]!.GetValue<string>(), StringComparer.Ordinal);
        Assert.Equal([null, group, group, group], projected.Select(value => SplitOf(value)));
        Assert.Equal(Ids(FirstSpace(session)["tabs"]), Ids(tabs));
        Assert.Equal([null, group, group, group], tabs.Select(tab => SplitOf(tab!)));
    }

    [Fact]
    public void SplitMetadataTravelsWithItsMembers() {
        var group = Fixed(1_190);
        var metadata = new JsonObject {
            ["id"] = SwiftId(group),
            ["customTitle"] = "Synced Research",
            ["titleModifiedAt"] = At(300),
            ["customIconSymbol"] = "crest.emoji:🛰️",
            ["iconModifiedAt"] = At(301),
            ["tint"] = new JsonObject { ["red"] = 0.2, ["green"] = 0.5, ["blue"] = 0.8, ["alpha"] = 1.0 },
            ["tintModifiedAt"] = At(302)
        };
        var session = SplitSession([group, group]);
        FirstSpace(session)["splitGroups"] = new JsonArray(metadata.DeepClone());
        var journal = new JournalUnderTest(Fixed(1_191));

        journal.Stage(session, at: 400);
        var materialized = FirstSpace(journal.Materialize(session));

        var expected = StoredSessionCodec.DecodeSplitGroup(metadata);
        Assert.Equal(expected, StoredSessionCodec.DecodeSplitGroup(Assert.Single(journal.Values(SyncRecordKind.Space)[0]["splitGroups"]!.AsArray())));
        Assert.Equal(expected, StoredSessionCodec.DecodeSplitGroup(Assert.Single(materialized["splitGroups"]!.AsArray())));
    }

    /// Positions, not the membership field, decide which tabs are neighbours: a
    /// tab that is no member between two members interrupts the run, and repair
    /// keeps the first run and clears the tail, the same way every time.
    [Fact]
    public void ANonMemberBetweenMembersClearsOnlyTheRunAfterIt() {
        var group = Fixed(1_150);
        var session = SplitSession([group, group, null, group]);
        var journal = new JournalUnderTest(Fixed(1_151));
        journal.Stage(session, at: 300);

        var materialized = journal.Materialize(session);

        var tabs = FirstSpace(materialized)["tabs"]!.AsArray();
        Assert.Equal(Ids(FirstSpace(session)["tabs"]), Ids(tabs));
        Assert.Equal([group, group, null, null], tabs.Select(tab => SplitOf(tab!)));
        Assert.Equal([group, group, null, null], FirstSpace(journal.Materialize(materialized))["tabs"]!.AsArray().Select(tab => SplitOf(tab!)));
    }

    /// A deletion's archive record is its audit trail. It cannot remove the live
    /// tab before the tab's own tombstone arrives, in whatever batch that is.
    [Fact]
    public void ADeletionAuditCannotRemoveALiveTabBeforeItsTombstone() {
        var session = OneSpaceSession();
        var space = FirstSpace(session);
        var tab = space["tabs"]![0]!.AsObject();
        var journal = new JournalUnderTest(Fixed(1_184));
        journal.Merge(SavedRecord(SyncRecordKind.Space, SpaceValue(space), 1, Fixed(200)),
            SavedRecord(SyncRecordKind.Tab, TabValue(tab, Fixed(100)), 10, Fixed(1_182)),
            SavedRecord(SyncRecordKind.Archive, new JsonObject {
                ["tab"] = TabValue(tab, Fixed(100)),
                ["archivedAt"] = At(500),
                ["reason"] = "deleted"
            }, 20, Fixed(1_183)));

        var materialized = FirstSpace(journal.Materialize(session));

        Assert.Contains(Fixed(102), Ids(materialized["tabs"]));
        Assert.Empty(materialized["archivedTabs"]!.AsArray());
    }

    [Theory]
    [InlineData("pinned")]
    [InlineData("saved")]
    public void AnOrdinaryArchiveFromTheCloudCannotReplaceAPinnedOrSavedTab(string placement) {
        var session = OneSpaceSession();
        var space = FirstSpace(session);
        var tab = space["tabs"]![0]!.AsObject();
        tab["placement"] = placement;
        var archived = TabValue(tab, Fixed(100));
        archived["placement"] = "current";
        var journal = new JournalUnderTest(Fixed(1_189));
        journal.Merge(SavedRecord(SyncRecordKind.Space, SpaceValue(space), 1, Fixed(200)),
            SavedRecord(SyncRecordKind.Tab, TabValue(tab, Fixed(100)), 10, Fixed(1_187)),
            SavedRecord(SyncRecordKind.Archive, new JsonObject { ["tab"] = archived, ["archivedAt"] = At(500), ["reason"] = "closed" },
                20, Fixed(1_188)));

        var materialized = FirstSpace(journal.Materialize(session));

        Assert.Equal(placement, materialized["tabs"]!.AsArray().Single(held => StoredSessionCodec.Identity(held!["id"]) == Fixed(102))!
            ["placement"]!.GetValue<string>());
        Assert.DoesNotContain(Fixed(102), ArchivedIds(materialized["archivedTabs"]));
    }

    [Fact]
    public void ANewerActivationDefeatsAStaleCleanupArchive() {
        var session = OneSpaceSession(activated: 300);
        var materialized = FirstSpace(CleanedUp(session, archivedAt: 200));

        Assert.Equal([Fixed(102)], Ids(materialized["tabs"]));
        Assert.Empty(materialized["archivedTabs"]!.AsArray());
    }

    [Fact]
    public void ANewerCleanupArchiveWinsOverStaleActivity() {
        var session = OneSpaceSession(activated: 100);
        var materialized = FirstSpace(CleanedUp(session, archivedAt: 200));

        Assert.DoesNotContain(Fixed(102), Ids(materialized["tabs"]));
        Assert.Contains(Fixed(102), ArchivedIds(materialized["archivedTabs"]));
    }

    /// Whether a Space uses Crest Passwords travels with it once someone chose;
    /// this device's default Space and where each Space keeps its passwords
    /// stay its own.
    [Fact]
    public void MaterializingTakesWhetherASpaceUsesCrestPasswordsAndKeepsThisDevicesDefaultSpaceAndPasswordStorage() {
        var source = SessionOf(FirstSpace(OneSpaceSession(Fixed(20_001), Fixed(20_002), Fixed(20_003))),
            FirstSpace(OneSpaceSession(Fixed(20_004), Fixed(20_005), Fixed(20_006))));
        source["spaces"]![1]!["credentialPreferences"] = new JsonObject {
            ["isEnabled"] = false,
            ["syncsCrestPasswordsWithICloud"] = true,
            ["alsoOffersSaveToSystemPasswords"] = false
        };
        source["spaces"]![1]!["credentialsEnabledModifiedAt"] = 800_000_100.0;
        var local = source.DeepClone().AsObject();
        local["defaultSpaceID"] = SwiftId(Fixed(20_001));
        local["spaces"]![0]!["credentialPreferences"] = new JsonObject { ["isEnabled"] = false };
        local["spaces"]![1]!["credentialPreferences"] = new JsonObject {
            ["isEnabled"] = true,
            ["syncsCrestPasswordsWithICloud"] = false,
            ["alsoOffersSaveToSystemPasswords"] = true
        };
        local["spaces"]![1]!.AsObject().Remove("credentialsEnabledModifiedAt");
        var journal = new JournalUnderTest(Fixed(20));
        journal.Stage(source);

        var result = journal.Materialize(local);

        Assert.Equal(Fixed(20_001), StoredSessionCodec.Identity(result["defaultSpaceID"]));
        var chosen = StoredSessionCodec.DecodeSpace(SpaceIn(result, Fixed(20_004))).Settings;
        Assert.Equal(new CredentialPreferences(IsEnabled: false, SyncsCrestPasswordsWithICloud: false, AlsoOffersSaveToSystemPasswords: true),
            chosen.CredentialPreferences);
        Assert.Equal(StoredSessionCodec.Date(800_000_100.0), chosen.CredentialsEnabledModifiedAt);
        // A Space nobody chose for keeps this device's own choice.
        Assert.False(StoredSessionCodec.DecodeSpace(SpaceIn(result, Fixed(20_001))).Settings.CredentialPreferences.IsEnabled);
    }

    /// A device that syncs neither current tabs nor history keeps its own of
    /// both, and still takes the Space's other values.
    [Fact]
    public void CategoriesThisDeviceDoesNotSyncKeepItsOwnContent() {
        var remote = OneSpaceSession();
        FirstSpace(remote)["name"] = "Renamed remotely";
        FirstSpace(remote)["history"] = new JsonArray(VisitOf(Fixed(21), "remote"));
        var local = remote.DeepClone().AsObject();
        FirstSpace(local)["tabs"] = new JsonArray(TabOf(Fixed(22), "Local current tab", "https://example.com/local", activated: 300));
        FirstSpace(local)["history"] = new JsonArray(VisitOf(Fixed(23), "local"));
        var journal = new JournalUnderTest(Fixed(24), currentTabs: false, historyAndArchive: false);
        journal.Stage(remote);

        var result = FirstSpace(journal.Materialize(local));

        Assert.Equal("Renamed remotely", result["name"]!.GetValue<string>());
        Assert.Equal("Local current tab", result["tabs"]![0]!["title"]!.GetValue<string>());
        Assert.Equal(["https://example.com/local"], result["history"]!.AsArray().Select(visit => visit!["url"]!.GetValue<string>()));
    }

    /// A native view this device pins takes no place from the pins the cloud
    /// brings: a full set of them still arrives.
    [Fact]
    public void ALocalNativePinDoesNotBlockAFullSetOfCloudPins() {
        var remote = CurrentTabSession(TabPlacement.PinnedCapacity);
        foreach (var tab in FirstSpace(remote)["tabs"]!.AsArray()) tab!["placement"] = "pinned";
        var journal = new JournalUnderTest(Fixed(25));
        journal.Stage(remote);
        var local = remote.DeepClone().AsObject();
        FirstSpace(local)["tabs"] = new JsonArray(NativeTabOf(Fixed(26), "settings", "Settings", "pinned"));

        var tabs = FirstSpace(journal.Materialize(local))["tabs"]!.AsArray();

        Assert.Equal(TabPlacement.PinnedCapacity + 1, tabs.Count);
        Assert.Equal(TabPlacement.PinnedCapacity, tabs.Count(tab => tab!["placement"]!.GetValue<string>() == "pinned"));
    }

    /// Records of native views an older build synced are retired: the first
    /// sync leaves them out, the next stage supersedes them, and the device's
    /// own view stays open.
    [Fact]
    public void NativeViewsAnOlderBuildSyncedAreRetiredWithoutClosingThisDevicesView() {
        var local = OneSpaceSession();
        var settings = NativeTabOf(Fixed(27), "settings", "Settings");
        FirstSpace(local)["tabs"]!.AsArray().Add(settings.DeepClone());
        var space = FirstSpace(local);
        var legacyValue = TabValue(settings, Fixed(100));
        legacyValue["nativeContent"] = new JsonObject { ["kind"] = "settings" };
        var journal = new JournalUnderTest(Fixed(28));
        journal.Merge(SavedRecord(SyncRecordKind.Space, SpaceValue(space), 1, Fixed(200)),
            SavedRecord(SyncRecordKind.Tab, legacyValue, 5, Fixed(1_701)));

        Assert.DoesNotContain(Fixed(27), Ids(FirstSpace(journal.Materialize(OneSpaceSession()))["tabs"]));
        journal.Stage(local, at: 200);

        Assert.Equal("superseded", journal.Record(SyncRecordKind.Tab, Fixed(27))!["tombstone"]!["reason"]!.GetValue<string>());
        var merged = FirstSpace(journal.Materialize(local));
        Assert.True(JsonNode.DeepEquals(Canonical(local)["spaces"]![0]!["tabs"]![1],
            merged["tabs"]!.AsArray().Single(tab => StoredSessionCodec.Identity(tab!["id"]) == Fixed(27))));
        Assert.DoesNotContain(Fixed(27), ArchivedIds(merged["archivedTabs"]));
    }

    /// A folder whose parent is recorded in another Space is no delivery order
    /// any batch explains, so materializing refuses it.
    [Fact]
    public void AFolderWhoseParentIsInAnotherSpaceIsRefused() {
        var session = OneSpaceSession();
        var space = FirstSpace(session);
        JsonObject Folder(Guid id, Guid owner, Guid? parent) {
            var value = new JsonObject {
                ["id"] = SwiftId(id),
                ["spaceID"] = SwiftId(owner),
                ["title"] = "Folder",
                ["symbol"] = "folder",
                ["location"] = "saved",
                ["orderToken"] = "a"
            };
            if (parent is { } container) value["parentID"] = SwiftId(container);
            return value;
        }
        var journal = new JournalUnderTest(Fixed(1_033));
        journal.Merge(SavedRecord(SyncRecordKind.Space, SpaceValue(space), 1, Fixed(200)),
            SavedRecord(SyncRecordKind.Folder, Folder(Fixed(1_031), Fixed(100), Fixed(1_030)), 2, Fixed(1_034)),
            SavedRecord(SyncRecordKind.Folder, Folder(Fixed(1_030), Fixed(1_032), null), 3, Fixed(1_034)));

        var refused = Assert.Throws<SyncRecordsFlawedException>(() => journal.Materialize(session));

        Assert.Equal(SyncRecordFlaw.InvalidFolderHierarchy, refused.Flaw);
        Assert.Equal(Fixed(100), refused.Subject);
    }

    #endregion

    #region Actions - Fixtures

    /// The split a tab or tab record names, or null.
    private static Guid? SplitOf(JsonNode tab) => StoredSessionCodec.OptionalIdentity(tab["splitGroupID"]);

    /// What `local` becomes once the cloud holds its tab and a cleanup archive
    /// of it made `archivedAt` seconds after 1970, written after the tab.
    private static JsonObject CleanedUp(JsonObject local, double archivedAt) {
        var space = FirstSpace(local);
        var tab = space["tabs"]![0]!.AsObject();
        var journal = new JournalUnderTest(Fixed(16));
        journal.Merge(SavedRecord(SyncRecordKind.Space, SpaceValue(space), 1, Fixed(200)),
            SavedRecord(SyncRecordKind.Tab, TabValue(tab, Fixed(100)), 10, Fixed(14)),
            SavedRecord(SyncRecordKind.Archive, new JsonObject {
                ["tab"] = TabValue(tab, Fixed(100)),
                ["archivedAt"] = At(archivedAt),
                ["reason"] = "autoCleanup"
            }, 20, Fixed(15)));
        return journal.Materialize(local);
    }

    #endregion
}
