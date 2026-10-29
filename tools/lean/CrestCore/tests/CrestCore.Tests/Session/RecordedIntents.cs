using System.Text;
using System.Text.Json.Nodes;

using CrestCore.Application;
using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Tests;

/// A clock a test sets.
internal sealed class TestClock(DateTimeOffset now) : IClock {
    #region Variables

    public DateTimeOffset Now { get; set; } = now;

    #endregion
}

/// The identities a test supplied, in order, and fresh ones once they run out.
internal sealed class TestIds : IIdSource {
    #region Variables

    private readonly Queue<Guid> supplied = [];

    #endregion

    #region Actions - Identity supply

    public void Supply(IEnumerable<Guid> ids) {
        foreach (var id in ids) supplied.Enqueue(id);
    }

    public Guid Next() => supplied.TryDequeue(out var id) ? id : Guid.NewGuid();

    #endregion
}

/// A recorded `history.visit`, which a page's engine reports now: a document
/// in the Space `SpaceId` finished at `Url`, titled `Title`, at `At`.
internal sealed record RecordedNavigation(Guid SpaceId, string Url, string Title, DateTimeOffset At);

/// The recorded session commands whose operations are typed intents or engine
/// reports now. A recorded step keeps the request the command sent, so the
/// step runs as what replaced it, at the time the request names.
internal static class RecordedIntents {
    #region Actions - Reading

    /// The intents a recorded request became, issued in `workspace` from
    /// `window` against the session `current` holds, or null for a request
    /// that is still a session command. A recorded Space creation carried the
    /// look the Space started with, which the core now picks itself, so it
    /// becomes the creation and the edits that dress the new Space as the
    /// recording did.
    public static IReadOnlyList<Intent>? Typed(JsonObject request, Guid workspace, Guid? window, SessionState current) {
        var arguments = request["arguments"] as JsonObject ?? [];
        Guid Id(string key) => Guid.Parse(request[key]!.GetValue<string>());
        Guid Argument(string key) => Guid.Parse(arguments[key]!.GetValue<string>());
        Guid? Optional(string key) => arguments[key] is { } value ? Guid.Parse(value.GetValue<string>()) : null;
        BrandColor? Color(JsonNode? value) => value is JsonObject color ? StoredSessionCodec.DecodeColor(color) : null;
        string Text(string key) => arguments[key]!.GetValue<string>();
        return request["operation"]!.GetValue<string>() switch {
            "tab.open" => [Opening(workspace, window ?? Guid.Empty, Id("spaceId"), arguments)],
            "tab.close" => [new CloseTab(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("tabId"))],
            "tab.transfer" => [new MoveTabToSpace(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("tabId"), Id("destinationSpaceId"),
                arguments["placement"] is { } placement ? TabPlacement.Named(placement.GetValue<string>()) : null, Optional("folderId"),
                Optional("before"), arguments["select"]?.GetValue<bool>() == true)],
            "archive.restore" => [new RestoreArchivedTab(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("tabId"))],
            "records.sweep" => [new SweepExpiredRecords(workspace)],
            "folder.create" => [new CreateFolder(workspace, Id("spaceId"), Argument("folderId"),
                TabPlacement.Named(Text("placement"))!, Optional("parentId"), arguments["title"]?.GetValue<string>(),
                Color(arguments["color"]),
                [.. (arguments["tabIds"] as JsonArray ?? []).Select(id => Guid.Parse(id!.GetValue<string>()))],
                arguments["detach"]?.GetValue<bool>() == true)],
            "split.join" => [new JoinSplit(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("tabId"), Argument("targetId"),
                arguments["index"]?.GetValue<int>())],
            "split.title" => [],
            "split.tint" => [],
            "space.identity" => [new SetSpaceIdentity(workspace, Id("spaceId"), Text("name"))],
            "space.reorder" => [new ReorderSpaces(workspace, Moved([.. current.Spaces.Select(space => space.Id)],
                [.. arguments["offsets"]!.AsArray().Select(offset => offset!.GetValue<int>())], arguments["destination"]!.GetValue<int>()))],
            "space.create" => Created(workspace, window ?? Guid.Empty, StoredSessionCodec.DecodeSpace(arguments["template"]), current),
            "space.deletion.begin" => [new BeginDeletingSpace(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("operationID"))],
            "space.remove" => [new FinishDeletingSpace(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("operationID"))],
            // These historical commands only changed preferences Crest no longer offers.
            "preferences.set" or "preferences.import" => [],
            "space.browsing_preferences" => Browsing(workspace, Id("spaceId"), StoredSessionCodec.DecodeBrowsingPreferences(arguments["value"])),
            "space.search_provider.upsert" => [],
            "space.search_provider.remove" => [],
            // A recorded import brought a file's Spaces.
            "workspace.import" => [new ImportSpaces(workspace, window ?? Guid.Empty,
                NativeWorkspaceImport.Decoded(Encoding.UTF8.GetBytes(arguments["sources"]!.ToJsonString())))],
            _ => null
        };
    }

    /// The tab a recorded `tab.open` gave the core whole, opened as the intent
    /// that names what it shows.
    private static OpenTab Opening(Guid workspace, Guid window, Guid space, JsonObject arguments) {
        var tab = StoredSessionCodec.DecodeTab(arguments["tab"]);
        return new(workspace, window, space, tab.Id, new TabContent(tab.Url, tab.NativeView, tab.Title), tab.Placement,
            arguments["after"] is { } after ? Guid.Parse(after.GetValue<string>()) : null, arguments["select"]?.GetValue<bool>() == true);
    }

    /// The navigation a recorded `history.visit` stands for, or null for any
    /// other request.
    public static RecordedNavigation? Navigation(JsonObject request) {
        if (request["operation"]!.GetValue<string>() != "history.visit") return null;
        var arguments = request["arguments"]!.AsObject();
        return new(Guid.Parse(request["spaceId"]!.GetValue<string>()), arguments["url"]!.GetValue<string>(),
            arguments["title"]?.GetValue<string>() ?? "", Time(request));
    }

    /// Supplies the actual native page facts captured by the recorded host.
    public static IReadOnlyList<Change> Send(CrestApp app, JsonObject request, IReadOnlyList<Intent> intents) {
        var appearances = (request["arguments"]?["copyObservations"] as JsonArray ?? []).Select(observed =>
            new TabPageAppearance(Guid.Parse(observed!["tabId"]!.GetValue<string>()), observed["url"]?.GetValue<string>(),
                observed["title"]!.GetValue<string>())).ToArray();
        var changes = new List<Change>();
        foreach (var intent in intents) {
            Intent prepared = intent switch {
                DuplicateTab copying => copying with { Appearances = appearances },
                DuplicateTabs copying => copying with { Appearances = appearances },
                SplitTabs copying => copying with { Appearances = appearances },
                JoinSplit copying => copying with { Appearances = appearances },
                OpenLinkInSplit copying => copying with { Appearances = appearances },
                DropIntoSplit copying => copying with { Appearances = appearances },
                _ => intent
            };
            changes.AddRange(app.Send(prepared));
        }
        return changes;
    }

    /// The recording's completed transient navigation, already deduplicated
    /// by the native page owner, becomes one atomic session record.
    public static IReadOnlyList<Change> Report(CrestApp app, RecordedNavigation navigation, Guid workspace) =>
        app.Send(new RecordPageNavigation(workspace, Guid.NewGuid(), navigation.SpaceId, null, navigation.Url,
            navigation.Title, navigation.At, app.Ids.Next(), HasIcon: false, IconAccent: null));

    /// The Spaces a recorded reorder left, which moved the ones at `offsets`
    /// to before the one at `destination`, as a list's move does.
    private static IReadOnlyList<Guid> Moved(IReadOnlyList<Guid> spaces, IReadOnlyList<int> offsets, int destination) {
        var moving = offsets.Distinct().Order().ToArray();
        var staying = spaces.Where((_, index) => !moving.Contains(index)).ToList();
        staying.InsertRange(destination - moving.Count(index => index < destination), moving.Select(index => spaces[index]));
        return staying;
    }

    /// A recorded creation as the core makes it, then renamed, dressed and
    /// protected as the recorded template was. The core names the Space
    /// itself, as it did then.
    private static IReadOnlyList<SessionIntent> Created(Guid workspace, Guid window, SpaceState template, SessionState current) => [
        new CreateSpace(workspace, window, template.Id),
        new SetSpaceIdentity(workspace, template.Id, $"Space {current.Spaces.Count + 1}"),
        .. Browsing(workspace, template.Id, template.Settings.BrowsingPreferences)
    ];

    /// The retained fields of recorded browsing preferences.
    private static IReadOnlyList<SessionIntent> Browsing(Guid workspace, Guid space, BrowsingPreferences preferences) => [
        new SetBrowsingPreferences(workspace, space, preferences.ContentBlocking, preferences.DataRetention)
    ];

    /// The identities a recorded request gave the records it made, which the
    /// core now gives them itself: a copy's, or a new Space's profile and tab.
    public static IEnumerable<Guid> Identities(JsonObject request) {
        if (request["arguments"]?["template"] is JsonObject template)
            return [Guid.Parse(template["profile"]!["id"]!.GetValue<string>()),
                Guid.Parse(template["tabs"]![0]!["id"]!["rawValue"]!.GetValue<string>())];
        return (request["arguments"]?["ids"] as JsonArray ?? []).Select(id => Guid.Parse(id!.GetValue<string>()));
    }

    /// When a recorded request ran.
    public static DateTimeOffset Time(JsonObject request) => StoredSessionCodec.Date(request["now"]!.GetValue<double>());

    #endregion
}
