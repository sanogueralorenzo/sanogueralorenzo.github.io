using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

public sealed class WorkspaceReviewTests {
    private static TabState Tab(string? url, TabPlacement? placement = null) {
        var chosen = placement ?? TabPlacement.Current;
        return new(Guid.NewGuid(), url ?? "Start Page", url, NativeContent: null, chosen.IsDurable ? url : null, "globe", FaviconUrl: null,
            IconAccent: null, StoredIconMode: null, chosen, FolderId: null, SplitGroupId: null, DateTimeOffset.UnixEpoch,
            PositionModifiedAt: null, CustomTitle: null, TitleModifiedAt: null, KeepsPageLoaded: false);
    }

    private static SpaceState Space(string name, params TabState[] tabs) => new(Guid.NewGuid(), Guid.NewGuid(),
        new SpaceSettings(name, "globe", SpaceAccent.Indigo, Branding: null, StoredSessionCodec.DefaultBrowsingPreferences,
            StoredSessionCodec.DefaultCredentialPreferences, SpaceAccessPolicy.Open, IsSavedTabsExpanded: true, SavedTabsExpansionModifiedAt: null),
        Folders: [], tabs, SplitGroups: [], ArchivedTabs: [], History: []);

    private static SessionState Session(Guid? seed, params SpaceState[] spaces) =>
        new(spaces, DefaultSpaceId: null, seed, SpaceDeletions: [], AppPreferences: null);

    [Fact]
    public void ReviewMatchesFoldedSpaceNamesAndLeavesOutTabsTheDestinationHolds() {
        var existingTab = Tab("https://example.com/a#section");
        var existing = Space("Wörk", existingTab);
        var duplicate = Tab("https://example.com/a"); var fresh = Tab("https://example.com/b"); var native = Tab(null);
        var source = Space(" work! ", duplicate, fresh, native);
        var unmatched = Space("!!!", Tab("https://example.com/a"));
        var review = SetupImportReview.Started(ImportSource.Arc, [source, unmatched], new Dictionary<Guid, int> { [source.Id] = 3 }, [], [], Session(null, existing), SetupLook.Heraldic);

        Assert.Equal(source.Id, review.ShownSpaceId);
        var joined = review.Spaces[0];
        Assert.Equal((existing.Id, "Wörk", 3), (joined.DestinationId, joined.Customization.Name, joined.PasswordCount));
        Assert.Equal([duplicate.Id], joined.DuplicateTabIds);
        Assert.Equal([fresh.Id, native.Id], joined.IncludedTabIds);
        Assert.Equal([existingTab.Id], joined.MatchedTabIds);
        Assert.Equal((null, "!!!"), (review.Spaces[1].DestinationId, review.Spaces[1].Customization.Name));
        // Over a first launch's disposable Spaces, everything comes in new.
        Assert.Null(SetupImportReview.Started(ImportSource.Arc, [source], new Dictionary<Guid, int>(), [], [], Session(Guid.NewGuid(), existing), SetupLook.Heraldic).Spaces[0].DestinationId);
    }

    [Fact]
    public void EditsFlagPinnedOverflowPerDestinationAndMatchOnlyIncludedSpaces() {
        var pinnedTabs = Enumerable.Range(0, 11).Select(index => Tab($"https://pinned.example/{index}", TabPlacement.Pinned)).ToArray();
        var existing = Space("Work", [.. pinnedTabs, Tab("https://example.com/a")]);
        var first = Tab("https://one.example", TabPlacement.Pinned); var second = Tab("https://two.example", TabPlacement.Pinned);
        var promoted = Tab("https://example.com/a");
        var source = Space("Work", first, second, promoted);
        var fresh = Space("New", Tab("https://three.example", TabPlacement.Pinned));
        var session = Session(null, existing);
        var review = SetupImportReview.Started(ImportSource.Chrome, [source, fresh], new Dictionary<Guid, int>(), [], [], session, SetupLook.Heraldic);

        review = review.Placing(source.Id, promoted.Id, TabPlacement.Pinned, session);
        Assert.Equal([second.Id, promoted.Id], review.OverflowTabIds);
        Assert.Equal([promoted.Id], review.Spaces[0].DuplicateTabIds);
        Assert.Equal([existing.Tabs[^1].Id], review.Spaces[0].MatchedTabIds);
        Assert.Empty(review.Spaces[1].DuplicateTabIds);
        // Joining another Space takes its name and look, and coming in new the Space's own.
        var joined = review.ChoosingDestination(fresh.Id, existing.Id, session, SetupLook.Heraldic);
        Assert.Equal((existing.Id, "Work"), (joined.Spaces[1].DestinationId, joined.Spaces[1].Customization.Name));
        Assert.Equal("New", joined.ChoosingDestination(fresh.Id, null, session, SetupLook.Heraldic).Spaces[1].Customization.Name);
        var dropped = review.IncludingSpace(source.Id, included: false, session);
        Assert.Empty(dropped.OverflowTabIds);
        Assert.Empty(dropped.Spaces[0].MatchedTabIds);
        Assert.Empty(dropped.Spaces[0].IncludedTabIds);
        Assert.Equal([promoted.Id], dropped.Spaces[0].DuplicateTabIds);
        // Bringing a tab back brings its Space, and bringing the Space leaves out what the destination holds.
        Assert.True(dropped.IncludingTabs(source.Id, [first.Id], included: true, session).Spaces[0].Included);
        Assert.Equal([first.Id, second.Id],
            dropped.IncludingSpace(source.Id, included: true, session).Spaces[0].IncludedTabIds);
    }

    [Fact]
    public void AReviewBringsNoMoreNewSpacesThanTheWorkspaceHoldsAndJoinsEachSpaceOnce() {
        var existing = Enumerable.Range(0, SessionState.MaximumSpaces - 1)
            .Select(index => Space($"Existing {index}", Tab($"https://existing{index}.example/"))).ToArray();
        var session = Session(null, existing);
        var joining = Space("Existing 0", Tab("https://joining.example/"));
        var again = Space(" EXISTING 0! ", Tab("https://again.example/"));
        var first = Space("First", Tab("https://first.example/"));
        var second = Space("Second", Tab("https://second.example/"));
        ImportLeftOut[] leftOut = [new("Big", new SessionOverLimits())];

        // The first Space matching an existing one joins it, and the next
        // comes in new; the workspace has room for one new Space only.
        var review = SetupImportReview.Started(ImportSource.Chrome, [joining, again, first, second], new Dictionary<Guid, int>(), [], leftOut,
            session, SetupLook.Heraldic);
        Assert.Equal([existing[0].Id, null, null, null], review.Spaces.Select(space => space.DestinationId));
        Assert.Equal([true, true, false, false], review.Spaces.Select(space => space.Included));
        Assert.Equal((0, leftOut), (review.NewSpaceCapacity, review.LeftOut));
        // Bringing another new Space past the room changes nothing, until one
        // joins an existing Space instead.
        Assert.Same(review, review.IncludingSpace(first.Id, included: true, session));
        Assert.Same(review, review.IncludingTabs(second.Id, [second.Tabs[0].Id], included: true, session));
        var joined = review.ChoosingDestination(again.Id, existing[1].Id, session, SetupLook.Heraldic);
        Assert.Equal(1, joined.NewSpaceCapacity);
        var full = joined.IncludingSpace(first.Id, included: true, session);
        Assert.Equal((true, 0), (full.Spaces[2].Included, full.NewSpaceCapacity));
        Assert.Same(full, full.ChoosingDestination(again.Id, null, session, SetupLook.Heraldic));
        // A first launch's disposable Spaces make way for every Space.
        Assert.Equal(SessionState.MaximumSpaces - 4, SetupImportReview.Started(ImportSource.Chrome, [joining, again, first, second],
            new Dictionary<Guid, int>(), [], [], Session(Guid.NewGuid(), existing), SetupLook.Heraldic).NewSpaceCapacity);
    }

    [Fact]
    public void ImportsRejectSplitRunsThatRepairWouldRewrite() {
        Guid group = Guid.NewGuid(), folder = Guid.NewGuid();
        SplitMember Member(TabPlacement? placement = null, Guid? inFolder = null) => new(group, placement ?? TabPlacement.Current, inFolder);
        SplitMember.RequireWellFormed([Member(), Member(), new(null, TabPlacement.Current, null)]);
        SplitMember.RequireWellFormed([Member()]);
        Assert.Throws<Rejected>(() => SplitMember.RequireWellFormed([Member(), Member(TabPlacement.Saved)]));
        Assert.Throws<Rejected>(() => SplitMember.RequireWellFormed([Member(), Member(inFolder: folder)]));
        Assert.Throws<Rejected>(() => SplitMember.RequireWellFormed([Member(TabPlacement.Pinned)]));
        Assert.Throws<Rejected>(() => SplitMember.RequireWellFormed(
            Enumerable.Repeat(Member(), BrowserTabCollection.MaximumSplitMembers + 1).ToArray()));
        Assert.Throws<Rejected>(() => SplitMember.RequireWellFormed(
            [Member(), new(null, TabPlacement.Current, null), Member()]));
    }
}
