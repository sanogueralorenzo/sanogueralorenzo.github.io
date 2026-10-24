using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    [Theory]
    [InlineData("getting-started")]
    [InlineData("future-native-view")]
    public void NativeContentKindsSurviveDomainRestoreAndSessionWrite(string kind) {
        var fixture = SavedSession();
        var session = fixture.Document["session"]!;
        var saved = session["spaces"]![0]!["tabs"]![0]!.AsObject();
        saved["url"] = null;
        saved["savedURL"] = null;
        saved["title"] = "Stored native title";
        saved["nativeContent"] = new JsonObject { ["kind"] = kind, ["resourceID"] = Guid.NewGuid().ToString().ToUpperInvariant() };

        var tab = BrowserTab.Restore(new TabState(fixture.Tab, "Stored native title", null, new NativeTabContent(kind), null, "square",
            null, null, null, TabPlacement.Saved, null, null, DateTimeOffset.UnixEpoch, null, null, null, false));
        Assert.Equal(TabRenderType.UiNative, tab.Content.RenderType);
        Assert.Equal(kind, tab.Content.NativeKind);
        Assert.Equal("Stored native title", tab.Title);

        // A rename runs the Space through the domain and back to its stored form.
        using var device = new TestDevice(session);
        var core = device.Authority;
        device.Send(new RenameTab(device.Workspace, fixture.Space, fixture.Tab, "Renamed"));
        var output = StoredSessionCodec.Encode(core.Current)["spaces"]![0]!["tabs"]![0]!;
        Assert.Equal("Renamed", output["customTitle"]!.GetValue<string>());
        Assert.True(JsonNode.DeepEquals(saved["nativeContent"], output["nativeContent"]));
        Assert.Equal("Stored native title", output["title"]!.GetValue<string>());
        Assert.Null(output["url"]);
    }
}
