using System.Globalization;
using System.Text.Json;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// The session's stored format belongs to Swift's Codable models, and Swift reads
/// the core's projections with them. These fixtures were written by the Swift
/// encoder: a session with every optional member set, and the installed session
/// the upgrade test carries. Command answers were recorded from the core before
/// it held typed records, for the same inputs, each issued from a window that
/// showed what the step's `window` names. A step whose command is a typed
/// intent now runs as that intent at the time it recorded, with the identities
/// it recorded, and the answers of the steps after it and the saved session
/// still match.
public sealed class StoredFormatTests {
    private static JsonObject Fixture(string name) =>
        JsonNode.Parse(File.ReadAllText(Path.Combine(AppContext.BaseDirectory, "Session", "Fixtures", name)))!.AsObject();

    private static Guid? Id(JsonNode? value) => value is null ? null : Guid.Parse(value.GetValue<string>());

    private static NativeSessionAuthority Load(JsonObject session) => TestWorkspaces.Session(session);

    /// The checkpoint's core part with each Space's history part put back.
    private static JsonObject Written(NativeSessionAuthority authority) {
        var checkpoint = authority.Checkpoint();
        var core = JsonNode.Parse(checkpoint.Read("core"))!.AsObject();
        foreach (var space in core["spaces"]!.AsArray())
            space!["history"] = JsonNode.Parse(checkpoint.Read(space["id"]!["rawValue"]!.GetValue<string>()));
        return core;
    }

    /// The stored session and the synced records spell each member of these
    /// sets as its name, so a renamed member would misread a person's data.
    [Fact]
    public void StoredSpellingsNeverChange() {
        Assert.Equal(["pinned", "saved", "current"], TabPlacement.All.Select(placement => placement.Name));
        Assert.Equal(["autoCleanup", "closed", "deleted", "deletedOnAnotherDevice", "quickWindow", "synced"],
            ArchiveReason.All.Select(reason => reason.Name));
        Assert.Equal(["autoCleanup", "closed", "closed", "synced", "quickWindow", "synced"],
            ArchiveReason.All.Select(reason => reason.StoredReason));
        Assert.Equal([null, null, "local", "remote", null, null], ArchiveReason.All.Select(reason => reason.DeletionOrigin));
        Assert.Equal(["automatic", "pulled", "emoji"], TabIconMode.All.Select(mode => mode.Name));
        Assert.Equal("crest.emoji:", TabIconMode.EmojiPrefix);
        Assert.Equal(["after12Hours", "after24Hours", "after7Days", "after30Days", "never"],
            CurrentTabCleanup.All.Select(cleanup => cleanup.Name));
        Assert.Equal(["oneDay", "oneWeek", "thirtyDays", "ninetyDays", "oneYear", "forever"], DataRetention.All.Select(retention => retention.Name));
        Assert.Equal(["after1Hour", "after6Hours", "after12Hours", "after24Hours", "never"],
            QuickWindowArchivePolicy.All.Select(policy => policy.Name));
        Assert.Equal(["balanced", "off"], ContentBlockingPolicy.All.Select(policy => policy.Name));
        Assert.Equal(["google", "duckDuckGo", "bing", "ecosia", "brave", "startpage", "kagi", "yahoo", "qwant", "chatGPT", "claude",
            "perplexity", "googleAIMode", "grok", "leChat", "duckAI", "copilotSearch", "kagiAssistant", "youTube", "wikipedia", "gitHub",
            "reddit", "x", "stackOverflow", "mdn", "amazon", "imdb", "spotify", "figmaCommunity", "googleMaps", "appleMaps", "googleImages",
            "googleTranslate", "wolframAlpha", "hackerNews", "npm", "appleDeveloper"], BuiltInSearchProvider.All.Select(provider => provider.Name));
        Assert.Equal("custom:", SearchProvider.CustomPrefix);
    }

    [Theory]
    [InlineData("maximal-session.json")]
    [InlineData("installed-session.json")]
    public void ASessionSwiftWroteIsWrittenBackUnchanged(string fixture) {
        var session = Fixture(fixture);
        var written = Written(Load(session));
        var differences = StoredJson.Differences(session, written, StoredJson.Comparison.Exact);
        Assert.True(differences.Count == 0, string.Join(Environment.NewLine, differences));
    }
}

/// Compares JSON the way a reader of the stored format does.
internal static class StoredJson {
    internal enum Comparison {
        /// Same members and values; numbers compare by value.
        Exact,
        /// As Swift's decoder reads them: an explicit null is an absent optional
        /// member, and two spellings of one UUID are the same identity.
        AsSwiftReads
    }

    public static IReadOnlyList<string> Differences(JsonNode? expected, JsonNode? actual, Comparison comparison, string path = "$") {
        var differences = new List<string>();
        Compare(expected, actual, comparison, path, differences);
        return differences;
    }

    private static void Compare(JsonNode? expected, JsonNode? actual, Comparison comparison, string path, List<string> differences) {
        if (expected is null || actual is null) {
            if (expected is not null || actual is not null) differences.Add($"{path}: expected {expected?.ToJsonString() ?? "null"}, found {actual?.ToJsonString() ?? "null"}");
            return;
        }
        switch (expected, actual) {
            case (JsonObject left, JsonObject right):
                foreach (var key in left.Select(member => member.Key).Union(right.Select(member => member.Key))) {
                    bool inLeft = left.TryGetPropertyValue(key, out var leftValue), inRight = right.TryGetPropertyValue(key, out var rightValue);
                    if (comparison == Comparison.Exact && inLeft != inRight)
                        differences.Add($"{path}.{key}: {(inLeft ? "missing" : "unexpected")}");
                    else Compare(leftValue, rightValue, comparison, $"{path}.{key}", differences);
                }
                return;
            case (JsonArray left, JsonArray right):
                if (left.Count != right.Count) { differences.Add($"{path}: expected {left.Count} items, found {right.Count}"); return; }
                for (int index = 0; index < left.Count; index++) Compare(left[index], right[index], comparison, $"{path}[{index}]", differences);
                return;
            case (JsonValue left, JsonValue right) when Same(left, right, comparison):
                return;
            default:
                differences.Add($"{path}: expected {expected.ToJsonString()}, found {actual.ToJsonString()}");
                return;
        }
    }

    private static bool Same(JsonValue left, JsonValue right, Comparison comparison) {
        if (left.GetValueKind() != right.GetValueKind()) return false;
        return left.GetValueKind() switch {
            JsonValueKind.Number => Number(left) == Number(right),
            JsonValueKind.String => left.GetValue<string>() == right.GetValue<string>()
                || comparison == Comparison.AsSwiftReads && Guid.TryParse(left.GetValue<string>(), out var a)
                    && Guid.TryParse(right.GetValue<string>(), out var b) && a == b,
            _ => left.ToJsonString() == right.ToJsonString()
        };
    }

    /// A number as its spelling reads, whether it was parsed or written as a
    /// value of any numeric type.
    private static double Number(JsonValue value) =>
        double.Parse(value.ToJsonString(), NumberStyles.Float, CultureInfo.InvariantCulture);
}
