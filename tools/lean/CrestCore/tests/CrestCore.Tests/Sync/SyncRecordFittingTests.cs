using System.Globalization;
using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    #region Static Variables

    /// Text of `bytes` UTF-8 bytes in three-byte characters, which a byte limit
    /// cuts mid-character unless it cuts at a character.
    private static string Wide(int characters) => new('語', characters);

    /// One character of 25 UTF-8 bytes, which a cut must keep whole.
    private const string Family = "👨‍👩‍👧‍👦";

    private static readonly string LongAddress = "https://example.com/" + new string('a', SyncedAddress.MaximumBytes);

    /// Each way a session can hold what no client reads in a record, and what
    /// its staged records carry instead.
    private static readonly Dictionary<string, (Action<JsonObject, JsonObject> Violate, Action<JsonArray> Expect)> FittingCases = new() {
        ["a long Space name"] = ((_, space) => space["name"] = new string('n', 300),
            records => Assert.Equal(new string('n', 128), Value(records, "space")["name"]!.GetValue<string>())),
        ["an unnamed Space"] = ((_, space) => space["name"] = "",
            records => Assert.Equal("Your Space", Value(records, "space")["name"]!.GetValue<string>())),
        ["a long folder title"] = ((_, space) => space["folders"]![0]!["title"] = Wide(200),
            records => Assert.Equal(Wide(170), Value(records, "folder")["title"]!.GetValue<string>())),
        ["an untitled folder"] = ((_, space) => space["folders"]![0]!["title"] = "",
            records => Assert.Equal("Folder", Value(records, "folder")["title"]!.GetValue<string>())),
        ["a long page title cut inside a character"] = ((tab, _) => tab["title"] = string.Concat(Enumerable.Repeat(Family, 100)),
            records => Assert.Equal(string.Concat(Enumerable.Repeat(Family, 81)), Value(records, "tab")["title"]!.GetValue<string>())),
        ["an untitled page"] = ((tab, _) => tab["title"] = "",
            records => Assert.Equal("example.com", Value(records, "tab")["title"]!.GetValue<string>())),
        ["a long rename"] = ((tab, _) => tab["customTitle"] = Wide(4_000),
            records => Assert.Equal(Wide(682), Value(records, "tab")["customTitle"]!.GetValue<string>())),
        ["a blank rename"] = ((tab, _) => tab["customTitle"] = "",
            records => Assert.Null(Value(records, "tab")["customTitle"])),
        ["a tab without a symbol"] = ((tab, _) => tab["symbol"] = "",
            records => Assert.Equal(TabIconMode.WebSymbol, Value(records, "tab")["symbol"]!.GetValue<string>())),
        ["a pinned tab that names a folder"] = ((tab, _) => tab["placement"] = TabPlacement.Pinned.Name,
            records => Assert.Null(Value(records, "tab")["folderID"])),
        ["an address past what sync carries"] = ((tab, _) => tab["url"] = LongAddress,
            records => Assert.DoesNotContain(records, record => Kind(record!) == "tab")),
        ["a saved address past what sync carries"] = ((tab, _) => tab["savedURL"] = LongAddress,
            records => Assert.DoesNotContain(records, record => Kind(record!) == "tab")),
        ["a long visit title"] = ((_, space) => space["history"]![0]!["title"] = Wide(1_000),
            records => Assert.Equal(Wide(682), Value(records, "history")["title"]!.GetValue<string>())),
        ["an untitled visit"] = ((_, space) => space["history"]![0]!["title"] = "",
            records => Assert.Equal("example.com", Value(records, "history")["title"]!.GetValue<string>())),
        ["a visit address past what sync carries"] = ((_, space) => space["history"]![0]!["url"] = LongAddress,
            records => Assert.DoesNotContain(records, record => Kind(record!) == "history")),
        ["an uncounted visit"] = ((_, space) => space["history"]![0]!["visitCount"] = 0,
            records => Assert.Equal(1, Value(records, "history")["visitCount"]!.GetValue<int>())),
        ["a visit first seen after it was last seen"] = ((_, space) => space["history"]![0]!["firstVisitedAt"] = 800000001.0,
            records => Assert.Equal(800000000.0, Value(records, "history")["firstVisitedAt"]!.GetValue<double>())),
        ["an archived tab with a long title"] = ((tab, space) => space["archivedTabs"] = new JsonArray(Archived(tab, Wide(1_000))),
            records => Assert.Equal(Wide(682), Value(records, "archive")["tab"]!["title"]!.GetValue<string>())),
    };

    public static TheoryData<string> FittingCaseNames { get; } = [.. FittingCases.Keys];

    #endregion

    #region Actions - Tests

    [Theory]
    [MemberData(nameof(FittingCaseNames))]
    public void StagingNeverWritesARecordAClientCannotRead(string name) {
        var (document, _, _) = SavedSession();
        var session = document["session"]!.AsObject();
        var space = session["spaces"]![0]!.AsObject();
        var tab = space["tabs"]![0]!.AsObject();
        var (violate, expect) = FittingCases[name];
        violate(tab, space);
        var stored = session.ToJsonString();

        var staged = NativeSyncJournal.Fresh(Guid.NewGuid()).Stage(session.DeepClone().AsObject(), SyncDeletionReason.Superseded, 800000100.0);

        var records = JsonNode.Parse(staged.Read())!["records"]!.AsArray();
        foreach (var record in records) Assert.Empty(ClientRefusals(record!["payload"]!));
        expect(records);
        // The session keeps what it holds; only its records are fitted.
        Assert.Equal(stored, session.ToJsonString());
    }

    #endregion

    #region Actions - Fixtures

    private static string Kind(JsonNode record) => record["id"]!["kind"]!.GetValue<string>();

    private static JsonObject Value(JsonArray records, string kind) =>
        Assert.Single(records, record => Kind(record!) == kind)!["payload"]!["value"]!.AsObject();

    private static JsonObject Archived(JsonObject tab, string title) {
        var archived = tab.DeepClone().AsObject();
        archived["id"] = SwiftId(Guid.NewGuid());
        archived["title"] = title;
        archived["placement"] = TabPlacement.Current.Name;
        archived.Remove("savedURL"); archived.Remove("folderID"); archived.Remove("splitGroupID");
        return new JsonObject { ["tab"] = archived, ["archivedAt"] = 800000050.0, ["reason"] = "closed" };
    }

    /// Why a client would refuse `payload`: each rule of the Apple clients'
    /// record validation that it breaks.
    private static List<string> ClientRefusals(JsonNode payload) {
        var refusals = new List<string>();
        var value = payload["value"]!;
        void Text(JsonNode? text, int limit, string field) {
            if (text?.GetValue<string>() is not { Length: > 0 } present || Encoding.UTF8.GetByteCount(present) > limit) refusals.Add(field);
        }
        void Address(JsonNode? address, string field) {
            var text = address?.GetValue<string>();
            if (text is null || Encoding.UTF8.GetByteCount(text) > SyncedAddress.MaximumBytes
                || !Uri.TryCreate(text, UriKind.Absolute, out var parsed) || parsed.Scheme is not ("http" or "https"))
                refusals.Add(field);
        }
        void Tab(JsonNode tab, string prefix) {
            Text(tab["title"], 2_048, prefix + ".title");
            if (tab["customTitle"] is { } custom) Text(custom, 2_048, prefix + ".customTitle");
            Text(tab["symbol"], 128, prefix + ".symbol");
            if (tab["url"]?.GetValue<string>() is { } url && url != "about:blank") Address(tab["url"], prefix + ".url");
            if (tab["placement"]!.GetValue<string>() == TabPlacement.Pinned.Name && tab["folderID"] is not null) refusals.Add(prefix + ".folderID");
        }
        switch (payload["type"]!.GetValue<string>()) {
            case "space":
                Text(value["name"], 128, "space.name");

                break;
            case "folder":
                Text(value["title"], 512, "folder.title");
                break;
            case "tab":
                Tab(value, "tab");
                break;
            case "history":
                Address(value["url"], "history.url");
                Text(value["title"], 2_048, "history.title");
                if (value["visitCount"]!.GetValue<int>() < 1
                    || value["firstVisitedAt"]!.GetValue<double>() > value["lastVisitedAt"]!.GetValue<double>())
                    refusals.Add("history.timestamps");
                break;
            case "archive":
                Tab(value["tab"]!, "archive.tab");
                if (TabPlacement.Named(value["tab"]!["placement"]!.GetValue<string>())!.IsDurable
                    || value["tab"]!["folderID"] is not null || value["tab"]!["splitGroupID"] is not null)
                    refusals.Add("archive.tab");
                break;
        }
        return refusals;
    }

    #endregion
}
