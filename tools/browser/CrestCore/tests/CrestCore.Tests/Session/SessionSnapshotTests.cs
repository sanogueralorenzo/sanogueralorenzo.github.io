using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void AcceptedAndPublishedSessionsOwnTheirNestedCollectionsIncludingCopies() {
        var source = TestWorkspaces.Seed(SavedSession().Document["session"]!);
        var original = source.Spaces[0];
        List<CustomSearchProvider> providers = [CustomSearchProvider.Carried(Guid.NewGuid(), "Search", "https://search.example/?q={searchTerms}", null)];
        List<BrandColor> colors = [new(0.1, 0.2, 0.3)];
        List<TranslationRule> rules = [new("en", "es", true)];
        var tabs = original.Tabs.ToList();
        var folders = original.Folders.ToList();
        var space = original with {
            Tabs = tabs,
            Folders = folders,
            Settings = original.Settings with {
                BrowsingPreferences = original.Settings.BrowsingPreferences with { CustomSearchProviders = providers },
                Branding = original.Settings.Look with { Colors = new ColorPalette(colors) }
            }
        };
        List<SpaceState> spaces = [space];
        List<SpaceDeletionState> deletions = [];
        var seed = source with {
            Spaces = spaces,
            SpaceDeletions = deletions,
            AppPreferences = (source.AppPreferences ?? AppPreferences.Default) with { TranslationRules = rules }
        };
        using var app = new CrestApp();
        var opened = Assert.Single(app.Send(new OpenWorkspace(WorkspaceKind.Persistent, seed)).OfType<WorkspaceOpened>());
        var accepted = StoredSessionCodec.Encode(opened.Session).ToJsonString();

        providers[0] = providers[0] with { Name = "Changed without an intent" };
        colors[0] = new(0.9, 0.8, 0.7);
        tabs.Clear();
        folders.Clear();
        spaces.Clear();
        rules.Clear();
        deletions.Add(new(Guid.NewGuid(), space.Id, space.ProfileId));

        Assert.Equal(accepted, StoredSessionCodec.Encode(app.Workspace(opened.WorkspaceId).Current).ToJsonString());
        Assert.Equal(accepted, StoredSessionCodec.Encode(opened.Session).ToJsonString());
        Assert.Empty(app.Drain());
        CannotReplace(opened.Session.Spaces, space);
        CannotReplace(opened.Session.Spaces[0].Tabs, original.Tabs[0]);
        CannotReplace(opened.Session.Spaces[0].Settings.BrowsingPreferences.CustomSearchProviders, providers[0]);
        CannotReplace(opened.Session.Spaces[0].Settings.Look.Colors.Colors, colors[0]);
        var sidebar = opened.Session.Spaces[0].Sidebar;
        foreach (var list in sidebar.Lists) {
            if (list.Rows.Count == 0) continue;
            CannotReplace(list.Rows, list.Rows[0]);
            if (list.Rows[0].Members.Count > 0) CannotReplace(list.Rows[0].Members, Guid.NewGuid());
        }
        var changes = app.Send(new RenameTab(opened.WorkspaceId, space.Id, space.Tabs[0].Id, "Through an intent"));
        Assert.Contains(changes, change => change is TabsChanged);
        Assert.Equal(accepted, StoredSessionCodec.Encode(opened.Session).ToJsonString());
    }

    private static void CannotReplace<T>(IReadOnlyList<T> values, T replacement) {
        if (values is IList<T> writable)
            Assert.Throws<NotSupportedException>(() => writable[0] = replacement);
    }
}
