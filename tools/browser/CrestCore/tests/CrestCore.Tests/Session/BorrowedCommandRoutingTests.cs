using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void ABorrowedWorkspaceLeavesSpaceSettingsToItsSourceWhichNormalizesBranding() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var owner = device.Authority;
        var borrowed = device.Borrow(session["spaces"]![0]!);
        var child = device.Session(borrowed);
        var space = SpaceId(session["spaces"]![0]!);
        var branding = StoredSessionCodec.DecodeBranding(new JsonObject { ["colors"] = new JsonArray(), ["bannerStrength"] = 2.0 });

        Assert.Equal(new BorrowedProfileRequiresOwner(borrowed),
            Assert.Throws<Rejected>(() => device.Send(new SetSpaceBranding(borrowed, space, branding))).Rejection);
        Assert.Equal(new BorrowedProfileRequiresOwner(borrowed),
            Assert.Throws<Rejected>(() => device.Send(new ReorderSpaces(borrowed, [space]))).Rejection);

        var changes = device.Send(new SetSpaceBranding(device.Workspace, space, branding));
        var stored = owner.Current.Spaces[0].Settings.Branding!;
        Assert.Single(stored.Colors.Colors);
        Assert.Equal(1.0, stored.BannerStrength);
        // The borrower takes the canonical branding from its source in the same answer.
        Assert.Equal(stored, child.Current.Spaces[0].Settings.Branding);
        Assert.Contains(changes, change => change is SpaceSettingsChanged { WorkspaceId: var workspace } && workspace == borrowed);
    }
}
