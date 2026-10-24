using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// A Space follows the device's default search or chooses its own, carries a
/// provider a person added so other devices and older builds still search
/// with it, and stores its choice in the spelling every build reads; the
/// first restore of the catalog keeps what Spaces chose before; new browsing
/// preferences sweep the Space under their retention.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void ASpaceFollowsTheDefaultSearchOrCarriesItsOwnInTheSpellingEveryBuildReads() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var core = device.Authority;
        var space = SpaceId(session["spaces"]![0]!);
        var kagi = Guid.NewGuid();
        JsonNode Stored() => JsonNode.Parse(core.Checkpoint().Read("core"))!["spaces"]![0]!["browsingPreferences"]!;
        SearchProvider Searches() => core.SearchCatalog.For(core.Current.Spaces[0].Settings.BrowsingPreferences, isPrivate: false);
        device.Send(new RestoreSearchCatalog("en", "US"));
        device.Send(new SaveSearchProvider(new(kagi, "  Kagi ", " https://kagi.com/search?q=%s ", "", SearchProviderKind.Engine, ["kg"], null)));
        var catalog = core.SearchCatalog;

        device.Send(new SetSpaceSearch(device.Workspace, space, catalog.Named(SearchProvider.CustomName(kagi)), SuggestionsEnabled: true));
        var preferences = Stored();
        Assert.Equal("custom:" + kagi.ToString("D"), preferences["selectedSearchProviderID"]!.GetValue<string>());
        // Builds that read only the legacy member fall back to Google.
        Assert.Equal("google", preferences["searchProvider"]!.GetValue<string>());
        Assert.Equal($"[{{\"id\":\"{kagi.ToString("D").ToUpperInvariant()}\",\"name\":\"Kagi\",\"searchURLTemplate\":\"https://kagi.com/search?q=%s\"}}]",
            preferences["customSearchProviders"]!.ToJsonString());
        Assert.Null(preferences["searchFollowsDefault"]);
        Assert.Equal("https://kagi.com/search?q=a", Searches().Search("a"));

        // Removing it from the device leaves the Space searching with the copy it carries.
        device.Send(new RemoveSearchProvider(kagi));
        Assert.Equal("https://kagi.com/search?q=a", Searches().Search("a"));

        device.Send(new SetDefaultSearch(core.SearchCatalog.Resolving(BuiltInSearchProvider.Brave)));
        device.Send(new SetSpaceSearch(device.Workspace, space, Provider: null, SuggestionsEnabled: null));
        Assert.Equal(("brave", "brave", true), (Stored()["selectedSearchProviderID"]!.GetValue<string>(),
            Stored()["searchProvider"]!.GetValue<string>(), Stored()["searchFollowsDefault"]!.GetValue<bool>()));
        Assert.Empty(Stored()["customSearchProviders"]!.AsArray());
        device.Send(new SetDefaultSearch(core.SearchCatalog.Resolving(BuiltInSearchProvider.ChatGPT)));
        Assert.Equal("chatGPT", Searches().Name);

        Assert.IsType<UnsuitableDefaultSearch>(Assert.Throws<Rejected>(() => device.Send(new SetSpaceSearch(device.Workspace, space,
            core.SearchCatalog.Resolving(BuiltInSearchProvider.YouTube), null))).Rejection);
        Assert.IsType<UnknownSearchEngine>(Assert.Throws<Rejected>(() => device.Send(new SetSpaceSearch(device.Workspace, space,
            CustomSearchProvider.Carried(Guid.NewGuid(), "Stranger", "https://stranger.example/?q=%s", null).Admitted() with { } is var stranger
                ? core.SearchCatalog.Saving(stranger).Custom[0].Provider : null, null))).Rejection);
    }

    [Fact]
    public void TheFirstRestoreKeepsWhatSpacesChoseAndTheyFollowTheDefaultItMakes() {
        var (document, _, _) = SavedSession();
        // Spaces a person chose, no longer the disposable seed of a first launch.
        document["session"]!.AsObject().Remove("disposableSeedMarker");
        var spaces = document["session"]!["spaces"]!.AsArray();
        var first = spaces[0]!;
        spaces.Add(first.DeepClone());
        spaces.Add(first.DeepClone());
        var engine = Guid.NewGuid();
        for (int index = 0; index < spaces.Count; index++) {
            var space = spaces[index]!;
            space["id"] = SwiftId(Guid.NewGuid());
            space["browsingPreferences"] = StoredSessionCodec.Encode(new BrowsingPreferences(
                index < 2 ? BuiltInSearchProvider.DuckDuckGo : null, index < 2 ? null : engine,
                index < 2 ? [] : [CustomSearchProvider.Carried(engine, "Example", "https://example.org/?q=%s", null)],
                SearchSuggestionsEnabled: index == 0, FollowsDefaultSearch: false, FollowsDefaultSuggestions: false, CurrentTabCleanup.Never,
                ContentBlockingPolicy.Balanced, new(DataRetention.Forever, DataRetention.Forever, DataRetention.Forever)));
        }
        using var device = new TestDevice(document["session"]!);
        var core = device.Authority;

        device.Send(new RestoreSearchCatalog("en", "GB"));

        var catalog = core.SearchCatalog;
        Assert.Equal(("duckDuckGo", false), (catalog.Default.Name, catalog.SuggestionsEnabled));
        Assert.Equal("https://example.org/?q=%s", Assert.Single(catalog.Custom).SearchUrlTemplate);
        var browsing = core.Current.Spaces.Select(space => space.Settings.BrowsingPreferences).ToList();
        Assert.Equal([true, true, false], browsing.Select(space => space.FollowsDefaultSearch));
        Assert.Equal([false, true, true], browsing.Select(space => space.FollowsDefaultSuggestions));
        Assert.Equal(engine, browsing[2].SelectedCustomEngineId);
        Assert.True(browsing[0].SearchSuggestionsEnabled);

        // A later restore only follows the device's language and region.
        device.Send(new RestoreSearchCatalog("de", "DE"));
        Assert.Equal(("duckDuckGo", "de"), (core.SearchCatalog.Default.Name, core.SearchCatalog.Language));
        Assert.Equal(browsing, core.Current.Spaces.Select(space => space.Settings.BrowsingPreferences));
    }

    [Fact]
    public void ADeviceThatRestoresAfterAnotherTakesItsDefaultAndLeavesEverySpaceAsItIs() {
        var (document, _, _) = SavedSession();
        var spaces = document["session"]!["spaces"]!.AsArray();
        spaces.Add(spaces[0]!.DeepClone());
        spaces[1]!["id"] = SwiftId(Guid.NewGuid());
        // Another device made Bing its default, which the first Space follows; the second chose Google.
        for (int index = 0; index < spaces.Count; index++)
            spaces[index]!["browsingPreferences"] = StoredSessionCodec.Encode(new BrowsingPreferences(
                index == 0 ? BuiltInSearchProvider.Bing : BuiltInSearchProvider.Google, null, [], SearchSuggestionsEnabled: index == 0,
                FollowsDefaultSearch: index == 0, FollowsDefaultSuggestions: index == 0, CurrentTabCleanup.Never, ContentBlockingPolicy.Balanced,
                new(DataRetention.Forever, DataRetention.Forever, DataRetention.Forever)));
        using var device = new TestDevice(document["session"]!);
        var before = device.Authority.Current.Spaces.Select(space => space.Settings.BrowsingPreferences).ToList();

        device.Send(new RestoreSearchCatalog("en", "US"));

        Assert.Equal(("bing", true), (device.Authority.SearchCatalog.Default.Name, device.Authority.SearchCatalog.SuggestionsEnabled));
        Assert.Equal(before, device.Authority.Current.Spaces.Select(space => space.Settings.BrowsingPreferences));
    }

    [Fact]
    public void NewBrowsingPreferencesSweepTheSpaceUnderTheirRetention() {
        var session = SavedSession().Document["session"]!;
        session["spaces"]![0]!["history"] = new JsonArray(new JsonObject {
            ["id"] = Guid.NewGuid().ToString(),
            ["url"] = "https://example.com/old",
            ["title"] = "Old visit",
            ["firstVisitedAt"] = 0.0,
            ["lastVisitedAt"] = 0.0,
            ["visitCount"] = 1
        });
        using var device = new TestDevice(session);
        var core = device.Authority;
        var space = core.Current.Spaces[0];
        var preferences = space.Settings.BrowsingPreferences;
        Assert.Single(space.History);

        device.Send(new SetBrowsingPreferences(device.Workspace, space.Id, CurrentTabCleanup.Never, preferences.ContentBlocking,
            preferences.DataRetention));
        Assert.Single(core.Current.Spaces[0].History);

        device.Send(new SetBrowsingPreferences(device.Workspace, space.Id, preferences.CurrentTabCleanup, preferences.ContentBlocking,
            preferences.DataRetention with { History = DataRetention.OneDay }));
        var swept = core.Current.Spaces[0];
        Assert.Empty(swept.History);
        Assert.Equal(DataRetention.OneDay, swept.Settings.BrowsingPreferences.DataRetention.History);
    }
}
