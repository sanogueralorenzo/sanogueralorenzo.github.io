using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

using Xunit;

namespace CrestCore.Tests;

/// Shared saved-session fixture for the native session, records, sync and
/// maintenance suites, in the shape the Swift encoder writes. It still carries
/// the selection fields older documents stored.
public sealed partial class BrowserContractsTests {
    private static IReadOnlyList<JsonObject> SpaceRecords(JsonNode session) {
        var space = Guid.Parse(session["spaces"]![0]!["id"]!["rawValue"]!.GetValue<string>());
        return NativeSyncProjection.Project(session.DeepClone().AsObject(), SyncProjectionPreferences(), [])
            .Select(payload => new JsonObject {
                ["id"] = new JsonObject {
                    ["kind"] = payload!["type"]!.DeepClone(),
                    ["value"] = (payload["type"]!.GetValue<string>() == "archive"
                        ? payload["value"]!["tab"]!["id"] : payload["value"]!["id"])!.DeepClone()
                },
                ["spaceID"] = SwiftId(space),
                ["version"] = new JsonObject { ["logicalClock"] = 1, ["deviceID"] = Guid.NewGuid().ToString() },
                ["payload"] = payload.DeepClone()
            }).ToArray();
    }


    private static JsonNode SessionWithSpaces(bool withSecondSpace = false) {
        var session = SavedSession().Document["session"]!;
        if (withSecondSpace)
            session["spaces"]!.AsArray().Add(SavedSession().Document["session"]!["spaces"]![0]!.DeepClone());
        return session;
    }
    private static (Guid Space, Guid Profile) FirstSpaceProfile(JsonNode session) => (
        Guid.Parse(session["spaces"]![0]!["id"]!["rawValue"]!.GetValue<string>()),
        Guid.Parse(session["spaces"]![0]!["profile"]!["id"]!.GetValue<string>()));

    private static JsonObject SwiftId(Guid value) => new() { ["rawValue"] = value.ToString().ToUpperInvariant() };

    /// A device showing a session under test in its windows. Commands name the
    /// window that issued them by `windowId`, and `Shown` answers what a window
    /// shows after every commit so far.
    private sealed class TestDevice : IDisposable {
        private readonly CrestApp app;
        private readonly Dictionary<Guid, WindowState> windows = [];

        /// A device with a workspace of `kind`, persistent unless named, opened
        /// from `session`, a document in the stored format.
        public TestDevice(JsonNode session, WorkspaceKind? kind = null) {
            app = new(new AppConfiguration(null, DevicePlatform.Desktop), Clock, Ids);
            Workspace = TestWorkspaces.Open(app, session, kind);
        }

        /// The workspace of the session the device was made for.
        public Guid Workspace { get; }

        /// The session of the workspace the device was made for.
        public NativeSessionAuthority Authority => app.Workspace(Workspace);

        /// The time the device's core stamps session intents with.
        public TestClock Clock { get; } = new(DateTimeOffset.UtcNow);

        /// The identities the device's core gives new records.
        public TestIds Ids { get; } = new();

        /// Opens another workspace of `kind` from `session` and answers it.
        public Guid Attach(JsonNode session, WorkspaceKind? kind = null) => TestWorkspaces.Open(app, session, kind);

        /// Opens a workspace that borrows `space`, a stored-format Space, of
        /// `owner`, the device's first workspace unless named, and answers it.
        public Guid Borrow(JsonNode space, Guid? owner = null) => TestWorkspaces.Borrow(app, owner ?? Workspace, space);

        /// The session of the workspace `workspace` names.
        public NativeSessionAuthority Session(Guid workspace) => app.Workspace(workspace);

        /// A window on the first session showing `space`, and `tabs` in the Spaces they name.
        public Guid Open(Guid? space, params (Guid Space, Guid? Tab)[] tabs) => OpenIn(Workspace, space, tabs);

        public Guid OpenIn(Guid workspace, Guid? space, params (Guid Space, Guid? Tab)[] tabs) {
            var id = Guid.NewGuid();
            Record(app.Send(new OpenWindow(id, workspace, Saved: false, CopyingWindowId: null, ShowingSpaceId: space,
                [.. tabs.Select(tab => new ShownTab(tab.Space, tab.Tab))], RestoresTabs: true)));
            return id;
        }

        /// A window on the first session showing what a fixture's legacy
        /// selection fields name.
        public Guid Showing(JsonNode session) => ShowingIn(Workspace, session);

        public Guid ShowingIn(Guid workspace, JsonNode session) => OpenIn(workspace,
            session["selectedSpaceID"] is { } space ? Guid.Parse(space["rawValue"]!.GetValue<string>()) : null,
            [.. session["spaces"]!.AsArray().Where(item => item!["selectedTabID"] is not null)
                .Select(item => (SpaceId(item!), (Guid?)Guid.Parse(item!["selectedTabID"]!["rawValue"]!.GetValue<string>())))]);

        public TAnswer Query<TAnswer>(Query<TAnswer> query) => app.Query(query);

        public IReadOnlyList<Change> Send(Intent intent) {
            var changes = app.Send(intent);
            Record(changes);
            return changes;
        }

        public WindowState Shown(Guid window) {
            Record(app.Drain());
            return windows[window];
        }

        public Guid Space(Guid window) => Shown(window).ShownSpaceId;

        /// The tab `window` shows in `space`, or null for none.
        public Guid? Tab(Guid window, Guid space) => Shown(window).ShownTabs.SingleOrDefault(tab => tab.SpaceId == space)?.TabId;

        public void Dispose() => app.Dispose();

        private void Record(IReadOnlyList<Change> changes) {
            foreach (var change in changes.OfType<WindowChanged>()) windows[change.Window.Id] = change.Window;
        }
    }

    private static (CrestApp App, Guid Workspace, Guid Window) WindowHost(JsonNode session, WorkspaceKind? kind = null) {
        var app = new CrestApp();
        var workspace = TestWorkspaces.Open(app, session, kind);
        var window = Guid.NewGuid();
        app.Send(new OpenWindow(window, workspace, Saved: false, null, null, [], RestoresTabs: true));
        return (app, workspace, window);
    }
    private static JsonNode TwoSpaceSession() {
        var session = SavedSession().Document["session"]!;
        session["spaces"]!.AsArray().Add(SavedSession().Document["session"]!["spaces"]![0]!.DeepClone());
        return session;
    }
    private static Guid ProfileId(JsonNode space) => Guid.Parse(space["profile"]!["id"]!.GetValue<string>());
    private static Rejection Refusal(CrestApp app, Intent intent) => Assert.Throws<Rejected>(() => app.Send(intent)).Rejection;

    private static Guid SpaceId(JsonNode space) => Guid.Parse(space["id"]!["rawValue"]!.GetValue<string>());

    /// The changes an intent answered without the saves the storage worker
    /// finished meanwhile, which join the pending batch whenever the worker
    /// gets to them.
    private static IReadOnlyList<Change> Own(IReadOnlyList<Change> changes) => [.. changes.Where(change => change is not Saved)];

    /// A Space's branding and browsing preferences as the Swift encoder wrote them.
    private const string SavedBrowsingPreferences = """
        {"contentBlockingPolicy":"balanced","searchSuggestionsEnabled":false,"searchProvider":"duckDuckGo","customSearchProviders":[],
        "selectedSearchProviderID":"duckDuckGo","dataRetention":{"archive":"forever","history":"forever","downloads":"forever"},
        "currentTabCleanupPolicy":"after12Hours"}
        """;
    private static (JsonObject Document, Guid Space, Guid Tab) SavedSession() {
        var space = Guid.NewGuid(); var tab = Guid.NewGuid();
        var folder = Guid.NewGuid();
        JsonObject savedTab = new() {
            ["id"] = SwiftId(tab),
            ["title"] = "Observed page",
            ["url"] = "https://example.com/article#one",
            ["placement"] = "saved",
            ["folderID"] = SwiftId(folder),
            ["savedURL"] = "https://example.com/",
            ["symbol"] = "crest.emoji:🌊",
            ["customTitle"] = "My reading",
            ["lastActivatedAt"] = 800000000.25,
            ["positionModifiedAt"] = 799999999.125,
            ["titleModifiedAt"] = 799999998.75,
            ["splitGroupID"] = SwiftId(Guid.NewGuid()),
            ["faviconURL"] = "https://example.com/favicon.ico",
            ["iconAccent"] = new JsonObject { ["red"] = 0.25, ["green"] = 0.5, ["blue"] = 0.75 }
        };
        JsonObject savedSpace = new() {
            ["id"] = SwiftId(space),
            ["profile"] = new JsonObject { ["id"] = Guid.NewGuid().ToString().ToUpperInvariant() },
            ["name"] = "Reading",
            ["symbol"] = "book",
            ["accent"] = "teal",
            ["accessPolicy"] = "open",
            ["browsingPreferences"] = JsonNode.Parse(SavedBrowsingPreferences),
            ["credentialPreferences"] = new JsonObject {
                ["isEnabled"] = false,
                ["syncsCrestPasswordsWithICloud"] = true,
                ["alsoOffersSaveToSystemPasswords"] = false
            },
            ["splitGroups"] = new JsonArray(),
            ["tabs"] = new JsonArray(savedTab),
            ["selectedTabID"] = SwiftId(tab),
            ["folders"] = new JsonArray(new JsonObject {
                ["id"] = SwiftId(folder),
                ["title"] = "Articles",
                ["location"] = "saved",
                ["isCollapsed"] = true,
                ["symbol"] = "book",
                ["color"] = new JsonObject { ["red"] = 0.7 }
            }),
            ["archivedTabs"] = new JsonArray(),
            ["history"] = new JsonArray(new JsonObject {
                ["id"] = Guid.NewGuid().ToString().ToUpperInvariant(),
                ["url"] = "https://example.com/article",
                ["title"] = "Earlier visit",
                ["firstVisitedAt"] = 799999990.0,
                ["lastVisitedAt"] = 800000000.0,
                ["visitCount"] = 4
            })
        };
        return (new JsonObject {
            ["session"] = new JsonObject {
                ["spaces"] = new JsonArray(savedSpace),
                ["selectedSpaceID"] = SwiftId(space),
                ["defaultSpaceID"] = SwiftId(space),
                ["disposableSeedMarker"] = Guid.NewGuid().ToString()
            }
        }, space, tab);
    }
}

/// Compares what two windows show, the Space and the tab in each Space,
/// leaving out what the core derives from them.
internal sealed class ShownComparer : IEqualityComparer<(Guid Space, IReadOnlyList<ShownTab> Tabs)> {
    public bool Equals((Guid Space, IReadOnlyList<ShownTab> Tabs) left, (Guid Space, IReadOnlyList<ShownTab> Tabs) right) =>
        left.Space == right.Space && left.Tabs.SequenceEqual(right.Tabs);

    public int GetHashCode((Guid Space, IReadOnlyList<ShownTab> Tabs) value) => value.Space.GetHashCode();
}
