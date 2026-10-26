using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void SyncOrderInsertionKeepsExistingTokensAndCompactsExhaustedGaps() {
        var original = SyncOrderTokens.Allocate([null, null, null]);
        var inserted = SyncOrderTokens.Allocate([original[0], null, original[1], original[2]]);
        Assert.Equal(original[0], inserted[0]); Assert.Equal(original[1], inserted[2]); Assert.Equal(original[2], inserted[3]);
        Assert.True(string.CompareOrdinal(inserted[0], inserted[1]) < 0);
        Assert.True(string.CompareOrdinal(inserted[1], inserted[2]) < 0);
        var compacted = SyncOrderTokens.Allocate(["0000000000000001", null, "0000000000000002"]);
        Assert.Equal(SyncOrderTokens.Allocate([null, null, null]), compacted);
        Assert.Equal(original, SyncOrderTokens.Allocate(["A", "invalid", null]));
    }

    private static JsonObject SyncTabRecord(Guid id, Guid space, ulong clock, Guid device) => new() {
        ["id"] = new JsonObject { ["kind"] = "tab", ["value"] = id.ToString() },
        ["spaceID"] = SwiftId(space),
        ["version"] = new JsonObject { ["logicalClock"] = clock, ["deviceID"] = device.ToString() },
        ["payload"] = new JsonObject {
            ["type"] = "tab",
            ["value"] = new JsonObject {
                ["id"] = SwiftId(id),
                ["spaceID"] = SwiftId(space),
                ["url"] = "https://example.com/",
                ["title"] = "Example",
                ["placement"] = "saved",
                ["lastActivatedAt"] = 50.0,
                ["orderToken"] = "7fffffffffffffff"
            }
        }
    };

    [Fact]
    public void SyncMergesPositionAndTitleIndependentlyAcrossEngineAgnosticRecords() {
        var first = SyncTabRecord(Guid.NewGuid(), Guid.NewGuid(), 1, Guid.NewGuid());
        var second = first.DeepClone().AsObject();
        second["version"]!["logicalClock"] = 10UL;
        var a = first["payload"]!["value"]!; var b = second["payload"]!["value"]!;
        a["positionModifiedAt"] = 80.0; a["placement"] = "pinned";
        a["futureProperty"] = "preserved when this record wins";
        b["positionModifiedAt"] = 60.0; b["lastActivatedAt"] = 70.0;
        b["customTitle"] = "Renamed on mobile"; b["titleModifiedAt"] = 90.0;
        b["futureProperty"] = "kept";
        var result = NativeSyncEvaluator.Resolve(first, second);
        Assert.Equal("pinned", result["payload"]!["value"]!["placement"]!.GetValue<string>());
        Assert.Equal("Renamed on mobile", result["payload"]!["value"]!["customTitle"]!.GetValue<string>());
        Assert.Equal("kept", result["payload"]!["value"]!["futureProperty"]!.GetValue<string>());
        Assert.True(JsonNode.DeepEquals(result, NativeSyncEvaluator.Resolve(second, first)));
        Assert.Equal("saved", b["placement"]!.GetValue<string>());
        b["spaceID"] = SwiftId(Guid.NewGuid());
        Assert.Throws<BrowserRuleException>(() => NativeSyncEvaluator.Resolve(first, second));
    }

}
