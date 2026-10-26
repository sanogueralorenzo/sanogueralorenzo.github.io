using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;

using Xunit;

namespace CrestCore.Tests;

/// Intents on the tabs and folders a person selected together: what each
/// does, which tab the window shows afterwards, and the rules that refuse a
/// selection, which change nothing.
public sealed partial class BrowserContractsTests {
    /// A session whose first Space holds, in order, a pinned tab, a saved tab
    /// in a saved folder, three open tabs of which the last two are a split,
    /// an open tab, and an open tab in an open folder; its second Space holds
    /// one open tab.
    private sealed class BatchSpace {
        public Guid Space { get; } = Guid.NewGuid();
        public Guid Other { get; } = Guid.NewGuid();
        public Guid Pinned { get; } = Guid.NewGuid();
        public Guid Saved { get; } = Guid.NewGuid();
        public Guid Open { get; } = Guid.NewGuid();
        public Guid Left { get; } = Guid.NewGuid();
        public Guid Right { get; } = Guid.NewGuid();
        public Guid Last { get; } = Guid.NewGuid();
        public Guid Filed { get; } = Guid.NewGuid();
        public Guid Resident { get; } = Guid.NewGuid();
        public Guid SavedFolder { get; } = Guid.NewGuid();
        public Guid OpenFolder { get; } = Guid.NewGuid();
        public Guid Split { get; } = Guid.NewGuid();
        public JsonNode Session { get; }

        public BatchSpace() {
            var fixture = SavedSession();
            Session = fixture.Document["session"]!;
            Session.AsObject().Remove("disposableSeedMarker");
            var space = Session["spaces"]![0]!.AsObject();
            space["id"] = SwiftId(Space);
            space["tabs"] = new JsonArray(Tab(Pinned, "pinned"), Tab(Saved, "saved", SavedFolder), Tab(Open, "current"),
                Tab(Left, "current", split: Split), Tab(Right, "current", split: Split), Tab(Last, "current"),
                Tab(Filed, "current", OpenFolder));
            space["folders"] = new JsonArray(Folder(SavedFolder, "saved"), Folder(OpenFolder, "current"));
            space["splitGroups"] = new JsonArray(new JsonObject { ["id"] = Split.ToString(), ["customTitle"] = "Research" });
            space.Remove("selectedTabID");
            var other = space.DeepClone().AsObject();
            other["id"] = SwiftId(Other);
            other["profile"] = new JsonObject { ["id"] = Guid.NewGuid().ToString() };
            other["tabs"] = new JsonArray(Tab(Resident, "current"));
            other["folders"] = new JsonArray();
            other["splitGroups"] = new JsonArray();
            other["history"] = new JsonArray();
            Session["spaces"]!.AsArray().Add(other);
            Session.AsObject().Remove("selectedSpaceID");
        }

        private static JsonObject Tab(Guid id, string placement, Guid? folder = null, Guid? split = null) => new() {
            ["id"] = SwiftId(id),
            ["title"] = "Page",
            ["url"] = $"https://batch.example/{id}",
            ["placement"] = placement,
            ["savedURL"] = placement == "current" ? null : $"https://batch.example/{id}",
            ["folderID"] = folder is { } folderId ? SwiftId(folderId) : null,
            ["splitGroupID"] = split is { } group ? SwiftId(group) : null,
            ["symbol"] = "globe",
            ["lastActivatedAt"] = 800000000.0
        };

        private static JsonObject Folder(Guid id, string location) => new() {
            ["id"] = SwiftId(id),
            ["title"] = "Folder",
            ["location"] = location
        };
    }

    /// The selection of `tabs`, as the window saw it.
    private static TabSelection Picking(params Guid[] tabs) => new(tabs, [], tabs);

    private static Guid[] Tabs(NativeSessionAuthority core, int space = 0) => [.. core.Current.Spaces[space].Tabs.Select(tab => tab.Id)];

    [Fact]
    public void DeletingASelectionIsSavedWithItsTombstonesBeforeItReturns() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var (core, sync) = (device.Authority, Syncing(device.Authority));
        var window = device.Open(f.Space, (f.Space, f.Saved));
        var staged = sync.Snapshot;

        device.Send(new DeleteTabs(device.Workspace, window, f.Space, Picking(f.Saved, f.Pinned)));
        // The deletion staged with the intent, not once edits paused.
        Assert.NotSame(staged, sync.Snapshot);
        var deleted = core.Current.Spaces[0].ArchivedTabs.TakeLast(2).ToArray();
        Assert.Equal([f.Pinned, f.Saved], deleted.Select(entry => entry.Tab.Id));
        Assert.All(deleted, entry => Assert.Equal((ArchiveReason.Deleted, TabPlacement.Current, (Guid?)null),
            (entry.Reason, entry.Tab.Placement, entry.Tab.FolderId)));
        // The window showed a deleted tab, and returns to the one it opened on.
        Assert.Equal(f.Open, device.Tab(window, f.Space));
        var records = JsonNode.Parse(sync.Snapshot.Read())!["records"]!.AsArray();
        foreach (var id in new[] { f.Saved, f.Pinned }) {
            var record = records.Single(record => record!["id"]!["kind"]!.GetValue<string>() == "tab"
                && Guid.Parse(record["id"]!["value"]!.GetValue<string>()) == id)!;
            Assert.Equal("explicitDelete", record["tombstone"]!["reason"]!.GetValue<string>());
        }
    }

    [Fact]
    public void ASelectionThatChangedSinceTheWindowSawItIsRefused() {
        var f = new BatchSpace();
        using var device = new TestDevice(f.Session);
        var core = device.Authority;
        var window = device.Open(f.Space, (f.Space, f.Open));
        var elsewhere = device.Open(f.Other);
        KeepTabsLoaded Keeping(TabSelection selection, Guid? from = null) => new(device.Workspace, from ?? window, f.Space, selection, true);
        var before = core.Current;

        // The folder holds a tab the window did not see, a tab is gone, or the
        // window shows another Space.
        Assert.IsType<SelectionChanged>(Assert.Throws<Rejected>(() => device.Send(Keeping(new([], [f.OpenFolder], [])))).Rejection);
        Assert.IsType<SelectionChanged>(device.Query(new CanSend(Keeping(Picking(f.Open, Guid.NewGuid())))).Refusal);
        Assert.IsType<SelectionChanged>(device.Query(new CanSend(Keeping(Picking(f.Open), elsewhere))).Refusal);
        Assert.Same(before, core.Current);

        // A folder's tabs keep their pages loaded with the rest.
        device.Send(Keeping(new([f.Open], [f.OpenFolder], [f.Open, f.Filed])));
        Assert.All(core.Current.Spaces[0].Tabs.Where(tab => tab.Id == f.Open || tab.Id == f.Filed), tab => Assert.True(tab.KeepsPageLoaded));
        device.Send(new SeparateSplits(device.Workspace, window, f.Space, Picking(f.Left, f.Right)));
        Assert.All(core.Current.Spaces[0].Tabs, tab => Assert.Null(tab.SplitGroupId));
    }

    private const int BrowserTabCollectionLimit = CrestCore.Domain.BrowserTabCollection.MaximumSplitMembers;
}
