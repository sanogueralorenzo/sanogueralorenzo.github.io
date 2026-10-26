using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// How the palette decides what leads and in what order: inline completion
/// follows other browsers and Return opens what the field shows, a place shows
/// once as its strongest kind, picks for the same text lead and can be
/// forgotten, a private window remembers nothing, site searches answer only
/// to their exact shortcut and search only their site, and what the palette
/// remembers survives the device store.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void APrivateWindowRemembersNothing() {
        var (session, space) = PaletteSession([], ("https://news.example.org/today", "Today", 1, 2, 1));
        using var device = new TestDevice(session, WorkspaceKind.Named("private"));
        var window = device.Open(space);
        var history = device.Query(Asking(window, "news")).Groups.SelectMany(group => group.Rows).First(row => row.Kind == PaletteRowKind.History);

        device.Send(new RecordPaletteChoice(window, "news", history));
        device.Send(new RecordPaletteChoice(window, "news", history));

        var answer = device.Query(Asking(window, "news"));
        Assert.Null(answer.Completion);
        Assert.DoesNotContain(answer.Groups.SelectMany(group => group.Rows), row => row.Reason == PaletteReason.Learned);
    }

    [Fact]
    public void StoredPalettePreferencesNameEveryKindOnceAndKeepWhatTheyCannotRead() {
        var stored = JsonNode.Parse("""
            {"layout":"spiral","showsTopHit":false,"sources":[
              {"source":"history","isEnabled":false,"limit":12},{"source":"history","isEnabled":true},{"source":"telepathy"},
              {"source":"openTabs","isEnabled":true,"limit":0}]}
            """);

        var preferences = StoredSessionCodec.DecodePalettePreferences(stored);

        Assert.Equal((PaletteLayout.Sections, false), (preferences.Layout, preferences.ShowsTopHit));
        // A number of rows outside what a person may choose is the kind's own.
        Assert.Equal((12, PaletteSection.Tabs.Limit), (preferences.Limit(PaletteSource.History), preferences.Limit(PaletteSource.OpenTabs)));
        Assert.Equal(PaletteSource.All.Count, preferences.Sources.Count);
        Assert.Equal([PaletteSource.History, PaletteSource.OpenTabs], preferences.Sources.Take(2).Select(choice => choice.Source));
        Assert.False(preferences.Offers(PaletteSource.History));
        Assert.Equal(PaletteSource.ArchivedTabs.IsEnabledByDefault, preferences.Offers(PaletteSource.ArchivedTabs));
        Assert.Equal(preferences, StoredSessionCodec.DecodePalettePreferences(StoredSessionCodec.Encode(preferences)));
    }

    /// A saved session with only `tabs` and `history` in its one Space, each
    /// history entry first and last visited that many days ago.
    private static (JsonNode Session, Guid Space) PaletteSession(JsonNode[] tabs,
        params (string Url, string Title, int Visits, double FirstDaysAgo, double LastDaysAgo)[] history) {
        var (document, space, _) = SavedSession();
        var saved = document["session"]!["spaces"]![0]!;
        saved["tabs"] = new JsonArray(tabs);
        saved["folders"] = new JsonArray();
        saved.AsObject().Remove("selectedTabID");
        double now = (DateTimeOffset.UtcNow - new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero)).TotalSeconds;
        saved["history"] = new JsonArray([.. history.OrderBy(entry => entry.LastDaysAgo).Select(entry => (JsonNode)new JsonObject {
            ["id"] = Guid.NewGuid().ToString().ToUpperInvariant(),
            ["url"] = entry.Url,
            ["title"] = entry.Title,
            ["firstVisitedAt"] = now - entry.FirstDaysAgo * 86_400,
            ["lastVisitedAt"] = now - entry.LastDaysAgo * 86_400,
            ["visitCount"] = entry.Visits
        })]);
        return (document["session"]!, space);
    }

    /// An open tab showing `url`, last used a week ago.
    private static JsonObject OpenTab(Guid id, string title, string url) => new() {
        ["id"] = SwiftId(id),
        ["title"] = title,
        ["url"] = url,
        ["placement"] = "current",
        ["symbol"] = "globe",
        ["lastActivatedAt"] = (DateTimeOffset.UtcNow.AddDays(-7) - new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero)).TotalSeconds
    };
}
