using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// History and tabs rank and complete addresses; clearing history removes its
/// results without a separate learned-choice store.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ClearingHistoryRemovesItsPaletteRowsAndCompletion() {
        var (session, space) = PaletteSession([], ("https://news.example.org/today", "Today", 1, 2, 1));
        using var device = new TestDevice(session);
        var window = device.Open(space);
        var before = device.Query(Asking(window, "news"));
        Assert.Equal(".example.org", before.Completion?.Suffix);
        Assert.Single(device.Query(Asking(window, "Today")).Groups.SelectMany(group => group.Rows), row => row.Kind == PaletteRowKind.History);

        device.Send(new ClearHistory(device.Workspace, space, BrowsingDataRange.AllTime));

        Assert.Null(device.Query(Asking(window, "news")).Completion);
        Assert.DoesNotContain(device.Query(Asking(window, "Today")).Groups.SelectMany(group => group.Rows), row => row.Kind == PaletteRowKind.History);
    }

    [Fact]
    public void CompletionIgnoresWwwStopsAtTheHostAndReturnOpensWhatTheFieldShows() {
        var (session, space) = PaletteSession([], ("https://www.amazon.de/gp/order-history", "Your Orders", 6, 400, 1));
        using var device = new TestDevice(session);
        var window = device.Open(space);

        var amazon = device.Query(Asking(window, "amazon"));
        Assert.Equal(new AddressCompletion("amazon", ".de", "amazon.de"), amazon.Completion);
        var lead = amazon.Groups[0].Rows[0];
        Assert.Equal(PaletteSection.TopHit, amazon.Groups[0].Section);
        Assert.Equal(("https://www.amazon.de/", PaletteReason.Completion), (lead.Address, lead.Reason));

        Assert.Equal("p/", device.Query(Asking(window, "amazon.de/g")).Completion!.Suffix);

        // After the person deletes the completion, Return runs what they typed.
        var held = device.Query(Asking(window, "amazon") with { AllowsCompletion = false });
        Assert.Null(held.Completion);
        Assert.Equal(PaletteRowKind.Search, held.Groups[0].Rows[0].Kind);
    }

    [Fact]
    public void ATypedSchemeOpensThePlaceInThatSchemeWhereTheSpaceKnowsItInAnother() {
        var (session, space) = PaletteSession([OpenTab(Guid.NewGuid(), "Privacy error", "https://10.0.0.1/")],
            ("https://10.0.0.1/", "Privacy error", 2, 3, 1));
        using var device = new TestDevice(session);
        var window = device.Open(space);

        var typed = device.Query(Asking(window, "http://10.0.0.1")).Groups.SelectMany(group => group.Rows).First();

        Assert.Equal((PaletteRowKind.OpenAddress, "http://10.0.0.1"), (typed.Kind, typed.Address));
    }

    [Fact]
    public void APlaceShowsOnceAsItsStrongestKind() {
        var (open, shown) = (Guid.NewGuid(), Guid.NewGuid());
        var (session, space) = PaletteSession([OpenTab(open, "Field notes", "https://example.org/notes"),
            OpenTab(shown, "Elsewhere", "https://elsewhere.example.net/")], ("http://www.example.org/notes", "Field notes", 3, 30, 2));
        using var device = new TestDevice(session);
        var window = device.Open(space, (space, shown));

        var rows = device.Query(Asking(window, "field notes")).Groups.SelectMany(group => group.Rows).ToList();

        Assert.Single(rows, row => row.TabId == open);
        Assert.DoesNotContain(rows, row => row.Kind == PaletteRowKind.History);
    }

    [Fact]
    public void BeforeAnythingIsTypedTheMostRecentOtherTabLeads() {
        var (older, recent, shown) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        var recentTab = OpenTab(recent, "Recipes", "https://recipes.example.org/");
        recentTab["lastActivatedAt"] = (DateTimeOffset.UtcNow.AddMinutes(-5) - new DateTimeOffset(2001, 1, 1, 0, 0, 0, TimeSpan.Zero)).TotalSeconds;
        var (session, space) = PaletteSession([OpenTab(older, "Garden plans", "https://garden.example.org/"), recentTab,
            OpenTab(shown, "Elsewhere", "https://elsewhere.example.net/")]);
        using var device = new TestDevice(session);
        var window = device.Open(space, (space, shown));
        PaletteAnswer Resting() =>
            device.Query(Asking(window, "") with { Commands = [new(ShortcutCommand.NewWindow, "New Window", "Everyday")] });

        // The tab the person was on before this one is the first row.
        var resting = Resting();
        Assert.Equal([PaletteSection.RecentTabs, PaletteSection.Actions], resting.Groups.Select(group => group.Section));
        Assert.Equal([recent, older], resting.Groups[0].Rows.Select(row => row.TabId));
    }

    [Fact]
    public void AScopeListsEveryRowOfItsKindBeforeAnythingIsTyped() {
        var (open, other, shown) = (Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid());
        var (session, space) = PaletteSession([OpenTab(open, "Garden plans", "https://garden.example.org/"),
            OpenTab(other, "Recipes", "https://recipes.example.org/"), OpenTab(shown, "Elsewhere", "https://elsewhere.example.net/")],
            ("https://news.example.org/today", "Today", 1, 2, 1));
        using var device = new TestDevice(session);
        var window = device.Open(space, (space, shown));

        var tabs = device.Query(Asking(window, "") with { Scope = PaletteScope.Tabs });
        Assert.Equal(new HashSet<Guid?> { open, other }, tabs.Groups.Single().Rows.Select(row => row.TabId).ToHashSet());
        Assert.Single(device.Query(Asking(window, "") with { Scope = PaletteScope.History }).Groups.Single().Rows);
    }

    [Theory]
    [InlineData("2+2*3", "8")]
    [InlineData("(1.5 + 2.5) ^ 2 / 4", "4")]
    [InlineData("10 % 4 − 1", "1")]
    [InlineData("42", null)]
    [InlineData("2/0", null)]
    [InlineData("2 apples", null)]
    public void TheCalculatorAnswersArithmeticWithAnOperatorOnly(string typed, string? answer) =>
        Assert.Equal(answer, Calculation.Of(typed)?.Answer);

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
