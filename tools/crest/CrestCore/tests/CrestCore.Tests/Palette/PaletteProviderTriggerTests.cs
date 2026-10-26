using System.Text.Json.Nodes;

using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    #region Actions - Provider Triggers

    [Theory]
    [InlineData(true)]
    [InlineData(false)]
    public void ExistingPalettePreferencesKeepTheirPreviousSpaceTrigger(bool tabEnabled) {
        var (session, space) = PaletteSession([]);
        session["appPreferences"] = new JsonObject {
            ["palette"] = new JsonObject { ["searchesSitesWithTab"] = tabEnabled }
        };
        using var device = new TestDevice(session);
        var answer = device.Query(Asking(device.Open(space), "$yt cats"));
        Assert.Equal(tabEnabled, answer.Entry?.Provider?.Name == "youTube");
    }

    [Fact]
    public void IndependentTriggerChoicesPersistAcrossRelaunch() {
        var (session, space) = PaletteSession([]);
        byte[] saved;
        using (var device = new TestDevice(session)) {
            var preferences = AppPreferences.Default with {
                Palette = PalettePreferences.Default with {
                    SearchesSitesWithTab = true,
                    ProviderSpaceTrigger = SearchProviderSpaceTrigger.Off
                }
            };
            device.Send(new SetAppPreferences(device.Workspace, preferences));
            saved = device.Authority.Checkpoint().Read("core");
        }
        using var relaunched = new TestDevice(JsonNode.Parse(saved)!);
        var restored = relaunched.Authority.Current.AppPreferences!.Palette;
        Assert.True(restored.SearchesSitesWithTab);
        Assert.Equal(SearchProviderSpaceTrigger.Off, restored.ProviderSpaceTrigger);
        var window = relaunched.Open(space);
        Assert.Null(relaunched.Query(Asking(window, "$yt cats")).Entry);
        Assert.NotNull(relaunched.Query(Asking(window, "yt")).OfferedSearch);
    }

    #endregion
}
