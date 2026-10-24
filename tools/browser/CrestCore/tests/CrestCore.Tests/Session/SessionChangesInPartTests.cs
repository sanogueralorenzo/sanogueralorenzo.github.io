using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// A list the change feed already found to hold each identity once is read
/// only where the next edit changed it, and publishes the same changes a read
/// of the whole list gives. In builds with cross-checks, which tests are,
/// every list is also read whole, and a difference throws.
public sealed class SessionChangesInPartTests {
    #region Static Variables

    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-25T12:00:00Z");

    #endregion

    #region Actions - Changes

    /// Moves, insertions, removals and visits after a first edit publish the
    /// rows they changed, and an order only when those rows' places do not
    /// give it.
    [Fact]
    public void AListEditedAgainPublishesOnlyItsChangedRows() {
        var (session, space) = Opened(tabs: 10, history: 6);
        var workspace = Guid.NewGuid();
        var tabs = space.Tabs;
        var history = space.History;

        // A tab moves to after another: no row changed, only the order.
        var moved = Editing(ref session, workspace, space.Id, [.. tabs.Take(2), .. tabs.Skip(3).Take(5), tabs[2], .. tabs.Skip(8)], history);
        var move = Assert.IsType<TabsChanged>(Assert.Single(moved));
        Assert.Empty(move.Updated);
        Assert.Empty(move.Removed);
        Assert.Equal(Current(session).Tabs.Select(tab => tab.Id), move.Order);

        // A tab opened at the end keeps every other row's place; one opened
        // first does not.
        var last = NewTab();
        var appended = Assert.IsType<TabsChanged>(Assert.Single(Editing(ref session, workspace, space.Id, [.. Current(session).Tabs, last],
            history)));
        Assert.Equal([last], appended.Updated);
        Assert.Null(appended.Order);
        var first = NewTab();
        var prepended = Assert.IsType<TabsChanged>(Assert.Single(Editing(ref session, workspace, space.Id,
            [first, .. Current(session).Tabs], history)));
        Assert.Equal([first], prepended.Updated);
        Assert.Equal(Current(session).Tabs.Select(tab => tab.Id), prepended.Order);

        // A closed tab is only removed; a renamed one only updated.
        var closing = Current(session).Tabs[4];
        var closed = Assert.IsType<TabsChanged>(Assert.Single(Editing(ref session, workspace, space.Id,
            [.. Current(session).Tabs.Where(tab => tab != closing)], history)));
        Assert.Equal([closing.Id], closed.Removed);
        Assert.Null(closed.Order);
        var renamed = Current(session).Tabs[6] with { CustomTitle = "Renamed" };
        var rename = Assert.IsType<TabsChanged>(Assert.Single(Editing(ref session, workspace, space.Id,
            [.. Current(session).Tabs.Select(tab => tab.Id == renamed.Id ? renamed : tab)], history)));
        Assert.Equal([renamed], rename.Updated);
        Assert.Null(rename.Order);

        // A new visit goes first; a visit to an older address moves its entry
        // first. Neither needs an order.
        var visited = HistoryEntryState.Visit(history, "https://new.example/", "New", Now, Guid.NewGuid())!;
        var visit = Assert.IsType<HistoryChanged>(Assert.Single(Editing(ref session, workspace, space.Id, Current(session).Tabs, visited)));
        Assert.Equal([visited[0]], visit.Recorded);
        Assert.Null(visit.Order);
        var revisited = HistoryEntryState.Visit(visited, history[3].Url, "Again", Now, Guid.NewGuid())!;
        var revisit = Assert.IsType<HistoryChanged>(Assert.Single(Editing(ref session, workspace, space.Id, Current(session).Tabs,
            revisited)));
        Assert.Equal([revisited[0]], revisit.Recorded);
        Assert.Empty(revisit.Removed);
        Assert.Null(revisit.Order);
    }

    /// A list that comes to hold one identity twice, beside a row the edit
    /// kept or in two rows it added, sends its Space again whole.
    [Fact]
    public void AListThatComesToHoldAnIdentityTwiceSendsItsSpaceWhole() {
        var edits = new Func<IReadOnlyList<HistoryEntryState>, IReadOnlyList<HistoryEntryState>>[] {
            history => [history[5] with { Title = "Copy" }, .. history],
            history => [.. history.Take(3), history[1] with { Title = "Copy" }, .. history.Skip(3)],
            history => [.. Twins(), .. history]
        };
        foreach (var edit in edits) {
            var (session, space) = Opened(tabs: 3, history: 8);

            var changes = Editing(ref session, Guid.NewGuid(), space.Id, space.Tabs, edit(space.History));

            var resent = Assert.IsType<SpacesChanged>(Assert.Single(changes));
            Assert.Equal([space.Id], resent.Removed);
            Assert.Equal([space.Id], resent.Added.Select(added => added.Id));
        }
    }

    #endregion

    #region Actions - Fixtures

    /// A session of one Space with `tabs` tabs and `history` entries, after a
    /// first edit to both lists, so the feed has read them whole once.
    private static (SessionState Session, SpaceState Space) Opened(int tabs, int history) {
        var space = SpaceTemplate.For(privateBrowsing: false).Make(Guid.NewGuid(), Guid.NewGuid(), Guid.NewGuid, number: 1, Now);
        space = space with {
            Tabs = [.. Enumerable.Range(0, tabs).Select(_ => NewTab())],
            History = [.. Enumerable.Range(0, history).Select(index => new HistoryEntryState(Guid.NewGuid(), $"https://visited-{index}.example/",
                $"Visited {index}", Now, Now, 1))]
        };
        var session = new SessionState([space], DefaultSpaceId: null, DisposableSeedMarker: null, SpaceDeletions: [], AppPreferences: null);
        var edited = space with { Tabs = [.. space.Tabs.Skip(1), space.Tabs[0]], History = [.. space.History.Skip(1), space.History[0]] };
        _ = Editing(ref session, Guid.NewGuid(), space.Id, edited.Tabs, edited.History);
        return (session, Current(session));
    }

    /// Replaces the Space's tabs and history in `session` and answers the
    /// changes the feed publishes for it.
    private static IReadOnlyList<Change> Editing(ref SessionState session, Guid workspace, Guid spaceId, IReadOnlyList<TabState> tabs,
        IReadOnlyList<HistoryEntryState> history) {
        var previous = session;
        var space = previous.Spaces.Single(candidate => candidate.Id == spaceId);
        session = previous with { Spaces = [space with { Tabs = tabs, History = history }] };
        return [.. SessionChanges.Publish(workspace, previous, session).Where(change => change is not SidebarChanged)];
    }

    private static SpaceState Current(SessionState session) => session.Spaces[0];

    /// Two new history entries with one identity.
    private static HistoryEntryState[] Twins() {
        var entry = new HistoryEntryState(Guid.NewGuid(), "https://twin.example/", "Twin", Now, Now, 1);
        return [entry, entry with { Url = "https://other-twin.example/" }];
    }

    private static TabState NewTab() {
        var id = Guid.NewGuid();
        return new TabState(id, $"Tab {id}", $"https://{id}.example/", NativeContent: null, SavedUrl: null, "globe", FaviconUrl: null,
            IconAccent: null, StoredIconMode: null, TabPlacement.Current, FolderId: null, SplitGroupId: null, Now, PositionModifiedAt: null,
            CustomTitle: null, TitleModifiedAt: null, KeepsPageLoaded: false);
    }

    #endregion
}
