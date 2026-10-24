using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Each edit's state is checked only for what the edit changed, against the
/// identities the accepted session keeps, and still refuses every flaw a whole
/// session would. In builds with cross-checks, which tests are, every check of
/// an edit is also run whole, and a disagreement throws.
public sealed class SessionIdentitiesTests {
    #region Static Variables

    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-25T12:00:00Z");

    #endregion

    #region Actions - Flaws

    /// An edit that gives a tab, a Space, a profile or a deletion an identity
    /// something else holds, or none, is refused for the flaw the whole session
    /// shows, whichever Space the edit changed and wherever the other holder is.
    [Fact]
    public void AnEditThatBreaksARuleIsRefusedForThatRule() {
        var (a, b, c) = (Space(5), Space(5), Space(5));
        var basis = Session(a, b, c);
        var deleting = new SpaceDeletionState(Guid.NewGuid(), b.Id, b.ProfileId);
        var cases = new (string Edit, SessionState Basis, SessionState Next, SessionFlaw Flaw)[] {
            ("B takes one of A's tabs", basis, Replacing(basis, b with { Tabs = [.. b.Tabs, a.Tabs[2]] }), SessionFlaw.DuplicateTab),
            ("A takes one of C's tabs", basis, Replacing(basis, a with { Tabs = [c.Tabs[4], .. a.Tabs] }), SessionFlaw.DuplicateTab),
            ("A holds one of its tabs twice", basis,
                Replacing(basis, a with { Tabs = [.. a.Tabs, a.Tabs[0] with { Title = "Copy" }] }), SessionFlaw.DuplicateTab),
            ("a tab of A becomes one of B's", basis,
                Replacing(basis, a with { Tabs = [.. a.Tabs.Select((tab, index) => index == 3 ? tab with { Id = b.Tabs[0].Id } : tab)] }),
                SessionFlaw.DuplicateTab),
            ("a tab moves within A and stays behind", basis,
                Replacing(basis, a with { Tabs = [a.Tabs[3], .. a.Tabs] }), SessionFlaw.DuplicateTab),
            ("two new tabs in A share an identity", basis, Replacing(basis, a with { Tabs = [.. a.Tabs, .. Twins()] }),
                SessionFlaw.DuplicateTab),
            ("A and B each open one tab with one identity", basis, Twinned(basis, a, b), SessionFlaw.DuplicateTab),
            ("a new tab has no identity", basis, Replacing(basis, b with { Tabs = [.. b.Tabs, b.Tabs[0] with { Id = Guid.Empty }] }),
                SessionFlaw.MissingIdentity),
            ("B takes A's profile", basis, Replacing(basis, b with { ProfileId = a.ProfileId }), SessionFlaw.SharedProfile),
            ("C loses its profile", basis, Replacing(basis, c with { ProfileId = Guid.Empty }), SessionFlaw.MissingIdentity),
            ("a new Space takes A's identity", basis, Adding(basis, Space(1) with { Id = a.Id }), SessionFlaw.DuplicateSpace),
            ("a new Space takes C's profile", basis, Adding(basis, Space(1) with { ProfileId = c.ProfileId }), SessionFlaw.SharedProfile),
            ("a new Space holds one of B's tabs", basis, Adding(basis, Space(1) with { Tabs = [b.Tabs[1]] }), SessionFlaw.DuplicateTab),
            ("a deletion names a Space the session lacks", basis,
                basis with { SpaceDeletions = [new(Guid.NewGuid(), Guid.NewGuid(), a.ProfileId)] }, SessionFlaw.UnknownDeletion),
            ("a deletion names A with B's profile", basis, basis with { SpaceDeletions = [new(Guid.NewGuid(), a.Id, b.ProfileId)] },
                SessionFlaw.UnknownDeletion),
            ("two deletions name B", basis with { SpaceDeletions = [deleting] },
                basis with { SpaceDeletions = [deleting, deleting with { Id = Guid.NewGuid() }] }, SessionFlaw.UnknownDeletion),
            ("a deletion has no identity", basis, basis with { SpaceDeletions = [deleting with { Id = Guid.Empty }] },
                SessionFlaw.MissingIdentity),
            ("the Space a deletion names takes a new profile", basis with { SpaceDeletions = [deleting] },
                Replacing(basis, b with { ProfileId = Guid.NewGuid() }) with { SpaceDeletions = [deleting] }, SessionFlaw.UnknownDeletion),
            ("the Space a deletion names goes", basis with { SpaceDeletions = [deleting] },
                basis with { Spaces = [a, c], SpaceDeletions = [deleting] }, SessionFlaw.UnknownDeletion),
        };

        foreach (var (edit, before, next, flaw) in cases) {
            var identities = Indexed(before);
            Assert.True(SessionIdentities.Flaw(next) == flaw, $"{edit}: the whole session shows {flaw}");
            Assert.True(identities.Flaw(before, next) == flaw, $"{edit}: the edit is refused for {flaw}");
        }
    }

    /// Edits that move, reorder, replace or retire identities without sharing
    /// one pass, including a tab that leaves one Space for another and a Space
    /// that goes while its tab moves on.
    [Fact]
    public void AnEditThatKeepsEveryIdentityUniqueIsTaken() {
        var (a, b, c) = (Space(5), Space(5), Space(5));
        var basis = Session(a, b, c);
        var moving = a.Tabs[1];
        var cases = new (string Edit, SessionState Next)[] {
            ("a tab moves from A to B", Replacing(Replacing(basis, a with { Tabs = [.. a.Tabs.Where(tab => tab != moving)] }),
                b with { Tabs = [moving, .. b.Tabs] })),
            ("A's tabs change order", Replacing(basis, a with { Tabs = [.. a.Tabs.Reverse()] })),
            ("a tab of A is renamed", Replacing(basis, a with { Tabs = [.. a.Tabs.Select(tab => tab with { Title = "Renamed" })] })),
            ("a tab of A takes a new identity", Replacing(basis, a with { Tabs = [a.Tabs[0] with { Id = Guid.NewGuid() }, .. a.Tabs.Skip(1)] })),
            ("the Spaces change order", basis with { Spaces = [c, a, b] }),
            ("A goes and its tab moves to C", basis with { Spaces = [b, c with { Tabs = [.. c.Tabs, moving] }] }),
            ("a new Space arrives with new tabs", Adding(basis, Space(3))),
        };

        foreach (var (edit, next) in cases) Assert.True(Indexed(basis).Flaw(basis, next) is null, $"{edit} breaks no rule");
    }

    /// The identities follow each accepted state: a tab that moved is held by
    /// the Space it moved to, and one that closed is free again.
    [Fact]
    public void TheIdentitiesFollowEachAcceptedState() {
        var (a, b) = (Space(4), Space(4));
        var basis = Session(a, b);
        var identities = Indexed(basis);
        var moving = a.Tabs[0];
        var closing = b.Tabs[3];

        var moved = Replacing(Replacing(basis, a with { Tabs = [.. a.Tabs.Skip(1)] }), b with { Tabs = [.. b.Tabs, moving] });
        Assert.Null(identities.Flaw(basis, moved));
        identities.Accepted(basis, moved);
        var movedA = moved.Spaces[0];

        // The moved tab now belongs to B, so A cannot take it back beside it.
        Assert.Equal(SessionFlaw.DuplicateTab, identities.Flaw(moved, Replacing(moved, movedA with { Tabs = [moving, .. movedA.Tabs] })));

        // A state accepted without a check of its own is followed too.
        var closed = Replacing(moved, moved.Spaces[1] with { Tabs = [.. moved.Spaces[1].Tabs.Where(tab => tab.Id != closing.Id)] });
        identities.Accepted(moved, closed);
        Assert.Null(identities.Flaw(closed, Replacing(closed, closed.Spaces[0] with { Tabs = [.. closed.Spaces[0].Tabs, closing] })));
        Assert.Equal(SessionFlaw.DuplicateTab,
            identities.Flaw(closed, Replacing(closed, closed.Spaces[0] with { Tabs = [.. closed.Spaces[0].Tabs, moving] })));
    }

    #endregion

    #region Actions - Scope

    /// An edit to one Space reads only that Space's tabs, and within it only
    /// the identities between the first and last tab whose identity changed.
    [Fact]
    public void AnEditReadsOnlyWhatItChanged() {
        var (a, b) = (Space(1_000), Space(1_000));
        var basis = Session(a, b);
        var identities = Indexed(basis);
        var opened = a.Tabs[0] with { Id = Guid.NewGuid() };

        Assert.Null(identities.Flaw(basis, Replacing(basis, a with { Tabs = [.. a.Tabs.Take(500), opened, .. a.Tabs.Skip(500)] })));
        Assert.Equal([a.Id], identities.Last!.Examined);
        Assert.Equal([opened.Id], identities.Last.Added);
        Assert.Empty(identities.Last.Removed);

        Assert.Null(identities.Flaw(basis, Replacing(basis, b with { Tabs = [.. b.Tabs.Select(tab => tab with { Title = "Renamed" })] })));
        Assert.Equal([b.Id], identities.Last!.Examined);
        Assert.Empty(identities.Last.Added);
    }

    #endregion

    #region Actions - Fixtures

    /// A Space with `tabs` current tabs, each with its own identity.
    private static SpaceState Space(int tabs) {
        var space = SpaceTemplate.For(privateBrowsing: false).Make(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid, number: 1, Now);
        var template = space.Tabs[0];
        return space with { Tabs = [.. Enumerable.Range(0, tabs).Select(_ => template with { Id = Guid.NewGuid() })] };
    }

    private static SessionState Session(params SpaceState[] spaces) => new(spaces, DefaultSpaceId: null, DisposableSeedMarker: null,
        SpaceDeletions: [], AppPreferences: null);

    private static SessionState Replacing(SessionState session, SpaceState space) =>
        session with { Spaces = [.. session.Spaces.Select(candidate => candidate.Id == space.Id ? space : candidate)] };

    private static SessionState Adding(SessionState session, SpaceState space) => session with { Spaces = [.. session.Spaces, space] };

    /// Two new tabs with one identity.
    private static TabState[] Twins() {
        var tab = Space(1).Tabs[0];
        return [tab, tab with { Title = "Twin" }];
    }

    /// `a` and `b` each open a new tab, both with one identity.
    private static SessionState Twinned(SessionState session, SpaceState a, SpaceState b) {
        var twins = Twins();
        return Replacing(Replacing(session, a with { Tabs = [.. a.Tabs, twins[0]] }), b with { Tabs = [.. b.Tabs, twins[1]] });
    }

    private static SessionIdentities Indexed(SessionState session) {
        var identities = new SessionIdentities();
        Assert.Null(identities.Index(session));
        return identities;
    }

    #endregion
}
