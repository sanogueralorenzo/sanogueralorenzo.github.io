using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    private static byte[] Bytes(JsonNode value) => Encoding.UTF8.GetBytes(value.ToJsonString());

    /// Names the first tab of `session`'s first Space `title`, in `workspace`.
    private static RenameTab Renaming(Guid workspace, JsonNode session, string title) {
        var space = session["spaces"]![0]!;
        return new(workspace, SpaceId(space), SpaceId(space["tabs"]![0]!), title);
    }

    [Fact]
    public void NativeAuthorityKeepsEarlierCheckpointStable() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var authority = device.Authority;
        var before = authority.Checkpoint();
        var original = before.Read("core");
        device.Send(Renaming(device.Workspace, session, "Updated native title"));
        Assert.Equal(original, before.Read("core"));
        var after = JsonNode.Parse(authority.Checkpoint().Read("core"))!;
        Assert.Equal("Updated native title", after["spaces"]![0]!["tabs"]![0]!["customTitle"]!.GetValue<string>());
        Assert.True(JsonNode.DeepEquals(session["spaces"]![0]!["branding"], after["spaces"]![0]!["branding"]));
        Assert.Empty(after["spaces"]![0]!["history"]!.AsArray());
    }

    [Fact]
    public void ALinkOpenedInADurableSplitCopiesItsMetadataAndTheSplitMovesOrDissolvesWhole() {
        var fixture = SavedSession(); var session = fixture.Document["session"]!;
        var space = session["spaces"]![0]!; var original = space["tabs"]![0]!;
        var peer = original.DeepClone(); peer["id"] = SwiftId(Guid.NewGuid());
        space["tabs"]!.AsArray().Add(peer);
        space["splitGroups"] = new JsonArray(new JsonObject {
            ["id"] = original["splitGroupID"]!.DeepClone(),
            ["customTitle"] = "Saved pair",
            ["titleModifiedAt"] = 800000000.0
        });
        var savedGroup = Guid.Parse(original["splitGroupID"]!["rawValue"]!.GetValue<string>());
        var folder = Guid.Parse(original["folderID"]!["rawValue"]!.GetValue<string>());
        using var device = new TestDevice(session);
        var core = device.Authority;
        var window = device.Showing(session);
        var linked = Guid.NewGuid();

        var changes = device.Send(new OpenLinkInSplit(device.Workspace, window, fixture.Space, linked, fixture.Tab,
            "https://example.org/link", "Link"));

        // The saved pair stays; open copies of it and the link make the split.
        Assert.Equal(2, changes.OfType<TabCopied>().Count());
        var updated = core.Current.Spaces[0];
        Assert.Equal(5, updated.Tabs.Count);
        var group = updated.Tabs.Single(tab => tab.Id == linked).SplitGroupId!.Value;
        Assert.NotEqual(savedGroup, group);
        Assert.Equal("Saved pair", updated.SplitGroups.Single(metadata => metadata.Id == group).CustomTitle);
        Assert.Equal(linked, device.Tab(window, fixture.Space));
        var before = core.Current;
        Assert.IsType<InvalidFolderPlacement>(Assert.Throws<Rejected>(() =>
            device.Send(new MoveSplit(device.Workspace, fixture.Space, group, TabPlacement.Pinned, null, null))).Rejection);
        Assert.Same(before, core.Current);
        device.Send(new MoveSplit(device.Workspace, fixture.Space, group, TabPlacement.Saved, folder, null));
        device.Send(new DissolveSplit(device.Workspace, fixture.Space, group));
        var final = core.Current.Spaces[0];
        Assert.Equal(5, final.Tabs.Count);
        Assert.All(final.Tabs, tab => Assert.Equal(TabPlacement.Saved, tab.Placement));
        Assert.Equal(savedGroup, Assert.Single(final.SplitGroups).Id);
        Assert.Equal(2, final.Tabs.Count(tab => tab.SplitGroupId is not null));
    }
}
