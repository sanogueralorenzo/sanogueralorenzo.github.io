using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// The persistent workspace imports the old settings once and keeps the
/// preferences on this device; the launch plan reads its startup choice.
public sealed partial class BrowserContractsTests {
    private static LaunchPlan LaunchPlan(Guid workspace, DevicePlatform? platform = null, LaunchEnvironment? environment = null) =>
        new(workspace, platform ?? DevicePlatform.Desktop, environment ?? LaunchEnvironment.Installed);

    private static LegacyAppPreferences LegacyPreferences() => new(StartupBehavior: "lastActiveTab", OffersTranslation: false,
        AutomaticallyTranslates: true, TranslationRules: """{"sources":{"es":{"isEnabled":true,"targetID":"en"}}}""",
        ChecksSpelling: true, AutomaticallyEntersPictureInPicture: false, SavedTabClosePolicy: "returnToSavedURL",
        SavedTabFaviconReturnsToSavedUrl: true, SplitFocusFollowsMouse: true);

    [Fact]
    public void LegacyPreferencesImportOnceAndPersistWithTheSession() {
        var session = SavedSession().Document["session"]!;
        byte[] saved;
        using (var device = new TestDevice(session)) {
            var authority = device.Authority;
            device.Send(new AdoptSetupCompletion(Completed: true));
            Assert.Equal(StartupBehavior.ShowStartPage, device.Query(LaunchPlan(device.Workspace)).Startup);
            device.Send(new ImportAppPreferences(device.Workspace, LegacyPreferences()));
            saved = authority.Checkpoint().Read("core");
        }
        var stored = JsonNode.Parse(saved)!["appPreferences"]!;
        Assert.Equal("lastActiveTab", stored["startupBehavior"]!.GetValue<string>());
        Assert.False(stored["offersTranslation"]!.GetValue<bool>());
        Assert.True(stored["automaticallyTranslates"]!.GetValue<bool>());
        Assert.Equal("en", stored["translationRules"]!["sources"]!["es"]!["targetID"]!.GetValue<string>());
        Assert.True(stored["checksSpelling"]!.GetValue<bool>());
        Assert.False(stored["automaticallyEntersPictureInPicture"]!.GetValue<bool>());
        Assert.Equal("returnToSavedURL", stored["savedTabClosePolicy"]!.GetValue<string>());
        Assert.True(stored["savedTabFaviconReturnsToSavedURL"]!.GetValue<bool>());
        Assert.True(stored["splitFocusFollowsMouse"]!.GetValue<bool>());

        // A later launch finds the record and never imports over it again.
        using var relaunched = new TestDevice(JsonNode.Parse(saved)!);
        var restored = relaunched.Authority;
        var kept = restored.Current.AppPreferences;
        relaunched.Send(new ImportAppPreferences(relaunched.Workspace, new("showStartPage", null, null, null, false, null, null, null,
            null)));
        Assert.Same(kept, restored.Current.AppPreferences);
        relaunched.Send(new AdoptSetupCompletion(Completed: true));
        Assert.Equal(StartupBehavior.LastActiveTab, relaunched.Query(LaunchPlan(relaunched.Workspace)).Startup);
    }

    [Fact]
    public void CloudReplacementNeverCarriesOrReplacesAppPreferences() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!.AsObject();
        session["appPreferences"] = new JsonObject { ["startupBehavior"] = "lastActiveTab", ["futureChoice"] = 3 };
        var journal = new NativeSyncJournal(Bytes(JournalDocument(SyncTabRecord(fixture.Tab, fixture.Space, 1, Guid.NewGuid()))));
        var transition = Transition(journal, session.DeepClone(), new JsonArray(), replacing: true, now: 800000000.0);
        Assert.True(JsonNode.DeepEquals(session["appPreferences"], transition.Materialization["session"]!["appPreferences"]));
    }
}
