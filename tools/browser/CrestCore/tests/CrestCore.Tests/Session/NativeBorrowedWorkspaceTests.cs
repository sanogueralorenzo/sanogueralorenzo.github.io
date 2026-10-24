using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed partial class BrowserContractsTests {
    [Fact]
    public void BorrowingUsesOwnedPolicyAndCannotCreateOrRewriteAProfileFromASnapshot() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var borrowed = device.Borrow(session["spaces"]![0]!);
        var child = device.Session(borrowed);
        var projected = JsonNode.Parse(child.Checkpoint().Read("core"))!;
        var source = session["spaces"]![0]!; var space = projected["spaces"]![0]!;
        Assert.True(JsonNode.DeepEquals(source["profile"], space["profile"]));
        foreach (var section in new[] { "tabs", "folders", "history", "archivedTabs", "splitGroups" })
            Assert.Empty(space[section]!.AsArray());
        Assert.Null(space["selectedTabID"]);
        var spaceId = SpaceId(source);
        Assert.Equal(new BorrowedProfileRequiresOwner(borrowed), Assert.Throws<Rejected>(() =>
            device.Send(new SetSpaceIdentity(borrowed, spaceId, "Not the owner", "globe", SpaceAccent.Teal))).Rejection);
        Assert.Equal(1UL, child.Revision);
        // A borrowed workspace opens only by borrowing, and only the Space's own profile.
        Assert.Equal(new BorrowedWorkspaceRequiresSpace(WorkspaceKind.Borrowed), Assert.Throws<Rejected>(() =>
            device.Send(new OpenWorkspace(WorkspaceKind.Borrowed, TestWorkspaces.Seed(projected)))).Rejection);
        Assert.Equal(new SpaceProfileChanged(spaceId), Assert.Throws<Rejected>(() =>
            device.Send(new BorrowSpace(device.Workspace, spaceId, Guid.NewGuid()))).Rejection);
        Assert.Equal(new BorrowedProfileRequiresOwner(borrowed), Assert.Throws<Rejected>(() =>
            device.Send(new BorrowSpace(borrowed, spaceId, device.Authority.Current.Spaces[0].ProfileId))).Rejection);
    }

    [Fact]
    public void ABorrowedSpaceFollowsItsOwnersSettingsAndKeepsItsOwnRecords() {
        var session = SavedSession().Document["session"]!;
        using var device = new TestDevice(session);
        var owner = device.Authority;
        var borrowed = device.Borrow(session["spaces"]![0]!);
        var child = device.Session(borrowed);
        var space = SpaceId(session["spaces"]![0]!);
        var window = device.OpenIn(borrowed, space);

        // A tab the borrowed workspace opens stays with it.
        var tab = Guid.NewGuid();
        device.Send(new OpenTab(borrowed, window, space, tab, new TabContent("https://example.org/", null, "Opened here"),
            TabPlacement.Current, null, false));
        Assert.Contains(child.Current.Spaces[0].Tabs, opened => opened.Id == tab);
        Assert.DoesNotContain(owner.Current.Spaces[0].Tabs, opened => opened.Id == tab);

        // The owner's edit reaches the borrowed Space in the same answer, as
        // the borrower's own change, and leaves its tabs alone.
        var changes = device.Send(new SetSpaceIdentity(device.Workspace, space, "New canonical name", "book", SpaceAccent.Teal));
        var followed = Assert.Single(changes.OfType<SpaceSettingsChanged>(), change => change.WorkspaceId == borrowed);
        Assert.Equal("New canonical name", followed.Settings.Name);
        Assert.Equal("New canonical name", child.Current.Spaces[0].Settings.Name);
        Assert.Contains(child.Current.Spaces[0].Tabs, opened => opened.Id == tab);
        // The borrowed session keeps nothing: following its owner saves nothing.
        Assert.Null(child.Storage);
    }

    [Fact]
    public void ABorrowedWorkspaceClosesOnceItsOwnerNoLongerLendsItsSpace() {
        var session = SavedSession().Document["session"]!;
        var extra = session["spaces"]![0]!.DeepClone();
        extra["id"] = SwiftId(Guid.NewGuid()); extra["profile"]!["id"] = Guid.NewGuid().ToString();
        extra["tabs"] = new JsonArray(); extra["selectedTabID"] = null;
        session["spaces"]!.AsArray().Add(extra);
        using var device = new TestDevice(session);
        var borrowed = device.Borrow(session["spaces"]![0]!);
        var child = device.Session(borrowed);
        var window = device.OpenIn(borrowed, SpaceId(session["spaces"]![0]!));
        var kept = child.Checkpoint().Read("core");

        // Deleting the Space closes its borrower within the owner's answer,
        // its window first, and leaves the borrower's records as they were.
        var changes = device.Send(new BeginDeletingSpace(device.Workspace, Guid.NewGuid(), SpaceId(session["spaces"]![0]!), Guid.NewGuid()));
        Assert.Equal([new WindowClosed(window), new WorkspaceClosed(borrowed)],
            changes.Where(change => change is WindowClosed or WorkspaceClosed));
        Assert.Equal(kept, child.Checkpoint().Read("core"));
        Assert.Equal(new UnknownWorkspace(borrowed), Assert.Throws<Rejected>(() =>
            device.Send(new SetSpaceIdentity(borrowed, SpaceId(session["spaces"]![0]!), "Gone", "book", SpaceAccent.Teal))).Rejection);

        // Closing the owner closes its borrowers first.
        var another = device.Borrow(extra);
        Assert.Equal([new WorkspaceClosed(another), new WorkspaceClosed(device.Workspace)],
            device.Send(new CloseWorkspace(device.Workspace)).OfType<WorkspaceClosed>());
    }
}
