using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// The persistent workspace keeps app preferences on this device.
public sealed partial class BrowserContractsTests {
    [Fact]
    public void AppPreferencesPersistWithTheSession() {
        var session = SavedSession().Document["session"]!;
        byte[] saved;
        using (var device = new TestDevice(session)) {
            var authority = device.Authority;
            device.Send(new SetAppPreferences(device.Workspace, AppPreferences.Default with { TranslationLanguage = "fr", SearchProvider = SearchProvider.DuckDuckGo }));
            saved = authority.Checkpoint().Read("core");
        }
        var stored = JsonNode.Parse(saved)!["appPreferences"]!;
        Assert.Equal("fr", stored["translationLanguage"]!.GetValue<string>());
        Assert.Equal("duckDuckGo", stored["searchProvider"]!.GetValue<string>());

        // A later launch keeps the saved choices.
        using var relaunched = new TestDevice(JsonNode.Parse(saved)!);
        var restored = relaunched.Authority;
        var kept = restored.Current.AppPreferences;
        Assert.Equal("fr", kept!.TranslationLanguage);
        Assert.Same(SearchProvider.DuckDuckGo, kept.SearchProvider);
    }

    [Fact]
    public void OnlyThePersistentWorkspaceKeepsAppPreferences() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var owner = device.Authority;
        var preferences = AppPreferences.Default with { TranslationLanguage = "fr" };
        device.Send(new SetAppPreferences(device.Workspace, preferences));
        Assert.Equal(preferences, owner.Current.AppPreferences);

        var borrowed = device.Borrow(session["spaces"]![0]!);
        var privateWorkspace = device.Attach(session.DeepClone(), WorkspaceKind.Private);
        foreach (var workspace in new[] { borrowed, privateWorkspace }) {
            Assert.Equal(new PersistentWorkspaceRequired(workspace), Assert.Throws<Rejected>(() =>
                device.Send(new SetAppPreferences(workspace, preferences))).Rejection);
        }
    }

    [Fact]
    public void CloudReplacementNeverCarriesOrReplacesAppPreferences() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        session["appPreferences"] = new JsonObject { ["translationLanguage"] = "fr", ["futureChoice"] = 3 };
        var journal = new NativeSyncJournal(Bytes(JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid()))));
        var transition = Transition(journal, session.DeepClone(), new JsonArray(), replacing: true, now: 800000000.0);
        Assert.True(JsonNode.DeepEquals(session["appPreferences"], transition.Materialization["session"]!["appPreferences"]));
    }

}
