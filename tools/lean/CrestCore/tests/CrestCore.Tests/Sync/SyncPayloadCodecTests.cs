using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// How the core reads and writes what synced records carry, as every Apple
/// client reads and writes it: each kind round-trips through both forms, the
/// fields older clients left out take the defaults those clients read, fields
/// a newer build added survive, and a record no client takes is unreadable.
public sealed partial class BrowserContractsTests {
    #region Static Variables

    private static readonly Guid CodecSpace = Guid.Parse("00000000-0000-4000-8000-00000000A001");
    private static readonly Guid CodecTab = Guid.Parse("00000000-0000-4000-8000-00000000A003");

    #endregion

    #region Actions - Tests

    [Theory]
    [InlineData("space", 1)]
    [InlineData("folder", 1)]
    [InlineData("tab", 1)]
    [InlineData("history", 1)]
    [InlineData("archive", 1)]
    public void EveryKindRoundTripsThroughTheCloudFormAtItsSchema(string kind, int schema) {
        var (id, space, value) = CodecValue(kind);
        var journal = CodecBody(kind, value);

        var read = SyncRecordBody.Read(journal, isTombstone: false, SyncPayloadForm.Journal);
        read.RequireSendable(SyncRecordKind.Named(kind)!, id, space);
        var cloud = read.Write(SyncPayloadForm.Cloud);
        var back = SyncRecordBody.Read(Bytes(cloud), isTombstone: false, SyncPayloadForm.Cloud);

        Assert.Equal(schema, read.Schema);
        Assert.True(NativeSyncEvaluator.Equivalent(cloud, back.Write(SyncPayloadForm.Cloud)), back.Write(SyncPayloadForm.Cloud).ToJsonString());
        Assert.Equal(cloud.Select(member => member.Key).Order(StringComparer.Ordinal), cloud.Select(member => member.Key));
    }

    /// The cloud spells dates in seconds since 1970 by adding the seconds
    /// between the epochs, and reading them back subtracts the same seconds,
    /// which is exact: a record read from the cloud writes the same seconds.
    [Fact]
    public void CloudDatesAreTheJournalsSecondsPlusTheEpochDistanceAndReadBackExactly() {
        var (_, _, value) = CodecValue("tab");
        value["lastActivatedAt"] = 811_615_335.98;
        var read = SyncRecordBody.Read(CodecBody("tab", value), isTombstone: false, SyncPayloadForm.Journal);

        double unix = read.Write(SyncPayloadForm.Cloud)["value"]!["lastActivatedAt"]!.GetValue<double>();
        var again = SyncRecordBody.Read(read.Bytes(SyncPayloadForm.Cloud), isTombstone: false, SyncPayloadForm.Cloud);

        Assert.Equal(811_615_335.98 + 978_307_200, unix);
        Assert.Equal(unix, again.Write(SyncPayloadForm.Cloud)["value"]!["lastActivatedAt"]!.GetValue<double>());
    }

    [Fact]
    public void RecordsOlderClientsWroteTakeTheDefaultsTheyRead() {
        var space = Legacy("space", "browsingPreferences", "accessPolicy", "credentialsEnabled", "credentialsEnabledModifiedAt");
        Assert.Equal("balanced", space["browsingPreferences"]!["contentBlockingPolicy"]!.GetValue<string>());
        // A Space whose record never said whether it uses Crest Passwords
        // leaves each device's own choice alone.
        Assert.Null(space["credentialsEnabled"]);

        var folder = Legacy("folder", "location", "color", "isCollapsed", "collapseModifiedAt");
        Assert.Equal("saved", folder["location"]!.GetValue<string>());
        Assert.Equal(0.43, folder["color"]!["red"]!.GetValue<double>());
        Assert.False(folder["isCollapsed"]!.GetValue<bool>());

        var tab = Legacy("tab", "positionModifiedAt", "customTitle", "titleModifiedAt");
        Assert.Null(tab["positionModifiedAt"]);
        Assert.Null(tab["customTitle"]);
    }

    /// Members a newer build writes that this one does not know survive both
    /// forms, around the envelope, inside the value, inside a nested member,
    /// and on a list's member, which follows its identity.
    [Fact]
    public void MembersANewerBuildWroteSurviveBothForms() {
        var (id, space, value) = CodecValue("space");
        value["futureSpace"] = ulong.MaxValue;
        value["futureItems"] = new JsonArray("kept");
        value["browsingPreferences"]!["dataRetention"]!["futureRetention"] = 4;
        var body = CodecBody("space", value);
        body["futureEnvelope"] = new JsonArray(true, "opaque", null);

        var cloud = SyncRecordBody.Read(body, isTombstone: false, SyncPayloadForm.Journal).Write(SyncPayloadForm.Cloud);
        var back = SyncRecordBody.Read(Bytes(cloud), isTombstone: false, SyncPayloadForm.Cloud).Write(SyncPayloadForm.Journal);

        Assert.True(JsonNode.DeepEquals(body["futureEnvelope"], back["futureEnvelope"]));
        Assert.Equal(ulong.MaxValue, back["value"]!["futureSpace"]!.GetValue<ulong>());
        Assert.Equal(4, back["value"]!["browsingPreferences"]!["dataRetention"]!["futureRetention"]!.GetValue<int>());
        Assert.True(JsonNode.DeepEquals(value["futureItems"], back["value"]!["futureItems"]));
        Assert.Equal(id, SpaceId(back["value"]!));
        Assert.Equal(space, SpaceId(back["value"]!));
    }

    [Theory]
    [InlineData("about:blank", true)]
    [InlineData("https://example.com/", true)]
    [InlineData("file:///private/secret", false)]
    [InlineData("javascript:alert(1)", false)]
    [InlineData("data:text/html,hello", false)]
    [InlineData("about:config", false)]
    [InlineData("about:blank?script=1", false)]
    public void OnlyWebAddressesAndTheBlankPageAreReadableTabAddresses(string url, bool readable) {
        var (_, _, value) = CodecValue("tab");
        value["url"] = url;

        Assert.Equal(readable, Readable("tab", value));
    }

    /// Records no client takes are unreadable, each for the rule it breaks.
    [Theory]
    [InlineData("tab", "orderToken", "\"ffffffffffffffffff\"")]
    [InlineData("tab", "orderToken", "\"zz\"")]
    [InlineData("tab", "placement", "\"sideways\"")]
    [InlineData("tab", "lastActivatedAt", "\"soon\"")]
    [InlineData("tab", "title", "\"\"")]
    [InlineData("folder", "location", "\"pinned\"")]
    [InlineData("history", "visitCount", "0")]
    [InlineData("history", "visitCount", "2.5")]
    [InlineData("archive", "reason", "\"vanished\"")]
    public void RecordsNoClientTakesAreUnreadable(string kind, string member, string json) {
        var (_, _, value) = CodecValue(kind);
        value[member] = JsonNode.Parse(json);

        Assert.False(Readable(kind, value));
    }

    [Fact]
    public void TheSchemaARecordNeedsFollowsWhatOlderClientsCannotPlace() {
        int Schema(string kind, Action<JsonObject> edit) {
            var (_, _, value) = CodecValue(kind);
            edit(value);
            return SyncRecordBody.Read(CodecBody(kind, value), isTombstone: false, SyncPayloadForm.Journal).Schema;
        }

        Assert.Equal(3, Schema("tab", value => {
            value["nativeContent"] = new JsonObject { ["kind"] = "settings" };
            value.Remove("url");
            value.Remove("savedURL");
        }));
        Assert.Equal(3, Schema("archive", value => {
            value["tab"]!["nativeContent"] = new JsonObject { ["kind"] = "settings" };
            value["tab"]!.AsObject().Remove("url");
        }));
        Assert.Equal(2, Schema("folder", value => value["location"] = "current"));
        Assert.Equal(2, Schema("tab", value => {
            value["placement"] = "current";
            value["folderID"] = SwiftId(Guid.NewGuid());
        }));
        Assert.Equal(1, Schema("tab", value => value["placement"] = "pinned"));
        Assert.Equal(1, SyncRecordBody.Read(Bytes(new JsonObject { ["reason"] = "explicitDelete", ["deletedAt"] = 800000000.0 }),
            isTombstone: true, SyncPayloadForm.Cloud).Schema);
    }

    /// The canonical RFC 3986 spelling staging writes parses on every client
    /// to the address Foundation parses from the original, and reading never
    /// refuses an address Foundation takes. Cases where Foundation and .NET's
    /// `Uri` disagree are listed first.
    [Theory]
    [InlineData(" https://example.com/lead", null, false, false)]
    [InlineData("https://example.com/trail ", "https://example.com/trail%20", true, true)]
    [InlineData("https://example.com/a b", "https://example.com/a%20b", true, true)]
    [InlineData("https://example.com/\\path", "https://example.com/%5Cpath", true, true)]
    [InlineData("https://münchen.de/straße", "https://xn--mnchen-3ya.de/stra%C3%9Fe", true, true)]
    [InlineData("https://例え.jp/", "https://xn--r8jz45g.jp/", true, true)]
    [InlineData("https://example.com:99999/", "https://example.com:99999/", true, true)]
    [InlineData("https://ex%41mple.com/", "https://ex%41mple.com/", true, true)]
    [InlineData("https://a..b/", "https://a..b/", true, true)]
    [InlineData("https:example.com", "https:example.com", false, true)]
    [InlineData("https://", "https://", false, true)]
    [InlineData("about:blank", "about:blank", false, false)]
    [InlineData("https://exa mple.com/", null, false, true)]
    [InlineData("https://example.com/%22{", "https://example.com/%2522%7B", true, true)]
    [InlineData("https://example.com:/a{", "https://example.com/a%7B", true, true)]
    [InlineData("https://u:p:q@example.com/", "https://u:p%3Aq@example.com/", true, true)]
    [InlineData("HTTP://EXAMPLE.com/Path", "HTTP://EXAMPLE.com/Path", true, true)]
    public void AnAddressIsSpelledAsEveryClientParsesItAndReadLeniently(string text, string? spelled, bool portable, bool readable) {
        var address = new SyncedAddress(text);

        Assert.Equal(spelled, address.Spelled);
        Assert.Equal(portable, address.IsPortable);
        Assert.Equal(readable, address.IsReadableWebAddress);
    }

    #endregion

    #region Actions - Fixtures

    /// A record of `kind` as the journal holds its value, with its identity and Space.
    private static (Guid Id, Guid Space, JsonObject Value) CodecValue(string kind) {
        var tab = new JsonObject {
            ["id"] = SwiftId(CodecTab),
            ["spaceID"] = SwiftId(CodecSpace),
            ["title"] = "Example",
            ["url"] = "https://example.com/a",
            ["savedURL"] = "https://example.com/",
            ["symbol"] = "globe",
            ["placement"] = "saved",
            ["orderToken"] = "7fffffffffffffff",
            ["lastActivatedAt"] = 811615335.98,
            ["positionModifiedAt"] = 811615336.123456,
            ["customTitle"] = "Mine",
            ["titleModifiedAt"] = 811615337.5
        };
        return kind switch {
            "space" => (CodecSpace, CodecSpace, new JsonObject {
                ["id"] = SwiftId(CodecSpace),
                ["profileID"] = Guid.NewGuid().ToString("D").ToUpperInvariant(),
                ["name"] = "Reading",
                ["symbol"] = "book",
                ["accent"] = "teal",
                ["browsingPreferences"] = JsonNode.Parse(SavedBrowsingPreferences),
                ["accessPolicy"] = "open",
                ["credentialsEnabled"] = false,
                ["credentialsEnabledModifiedAt"] = 800_000_020.0,
                ["splitGroups"] = new JsonArray(new JsonObject {
                    ["id"] = SwiftId(Guid.NewGuid()),
                    ["customTitle"] = "Research",
                    ["titleModifiedAt"] = 800000001.5
                }),
                ["orderToken"] = "8000000000000000"
            }),
            "folder" => (CodecTab, CodecSpace, new JsonObject {
                ["id"] = SwiftId(CodecTab),
                ["spaceID"] = SwiftId(CodecSpace),
                ["location"] = "saved",
                ["title"] = "Articles",
                ["symbol"] = "book",
                ["color"] = new JsonObject { ["red"] = 0.7, ["green"] = 0.2, ["blue"] = 0.1, ["alpha"] = 1.0 },
                ["isCollapsed"] = true,
                ["collapseModifiedAt"] = 800000004.75,
                ["orderToken"] = "4000000000000000"
            }),
            "history" => (CodecTab, CodecSpace, new JsonObject {
                ["id"] = CodecTab.ToString("D").ToUpperInvariant(),
                ["spaceID"] = SwiftId(CodecSpace),
                ["url"] = "https://example.com/visit",
                ["title"] = "Visit",
                ["firstVisitedAt"] = 800000000.1,
                ["lastVisitedAt"] = 800000010.2,
                ["visitCount"] = 4
            }),
            "archive" => (CodecTab, CodecSpace, new JsonObject {
                ["tab"] = Archived(tab),
                ["archivedAt"] = 800000020.5,
                ["reason"] = "closed"
            }),
            _ => (CodecTab, CodecSpace, tab)
        };
        static JsonObject Archived(JsonObject tab) {
            var archived = tab.DeepClone().AsObject();
            archived["placement"] = "current";
            archived.Remove("savedURL");
            return archived;
        }
    }

    /// A payload of `kind` holding `value`.
    private static JsonObject CodecBody(string kind, JsonObject value) => new() { ["type"] = kind, ["value"] = value.DeepClone() };

    /// Whether a client takes a record of `kind` holding `value`.
    private static bool Readable(string kind, JsonObject value) {
        var (id, space, _) = CodecValue(kind);
        try {
            SyncRecordBody.Read(CodecBody(kind, value), isTombstone: false, SyncPayloadForm.Cloud).RequireRecord(SyncRecordKind.Named(kind)!, id, space);
            return true;
        } catch (UnreadableSyncPayloadException) {
            return false;
        }
    }

    /// The value of a record of `kind` an older client wrote without
    /// `members`, as this build reads it and writes it to the journal.
    private static JsonNode Legacy(string kind, params string[] members) {
        var (_, _, value) = CodecValue(kind);
        foreach (string member in members) value.Remove(member);
        return SyncRecordBody.Read(CodecBody(kind, value), isTombstone: false, SyncPayloadForm.Cloud).Write(SyncPayloadForm.Journal)["value"]!;
    }

    #endregion
}
