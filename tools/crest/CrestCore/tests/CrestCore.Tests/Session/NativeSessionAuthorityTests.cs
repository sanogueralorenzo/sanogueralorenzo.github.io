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
}
