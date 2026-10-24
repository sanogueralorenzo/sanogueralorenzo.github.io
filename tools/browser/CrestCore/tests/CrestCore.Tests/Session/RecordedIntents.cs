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

/// Grants a test gives as the device owner authenticating would.
internal static class TestGrants {
    #region Actions - Unlocking

    /// Unlocks `space` of `workspace` through `send`, when it is locked.
    public static void Unlock(Func<Intent, IReadOnlyList<Change>> send, Guid workspace, Guid space) {
        var request = Guid.NewGuid();
        if (send(new BeginUnlockingSpace(workspace, space, request)).OfType<SpaceLockChanged>().Any(change => change.IsAuthenticating))
            send(new FinishUnlockingSpace(space, request, Authenticated: true));
    }

    /// Unlocks every Space of `session` that asks for authentication, as a
    /// person does before editing it.
    public static void UnlockGuarded(Func<Intent, IReadOnlyList<Change>> send, Guid workspace, SessionState session) {
        foreach (var space in session.Spaces.Where(space => space.Settings.AccessPolicy != SpaceAccessPolicy.Open
            && session.SpaceDeletions.All(deletion => deletion.SpaceId != space.Id)))
            Unlock(send, workspace, space.Id);
    }

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
                Color(arguments["color"]), arguments["symbol"]?.GetValue<string>(),
                [.. (arguments["tabIds"] as JsonArray ?? []).Select(id => Guid.Parse(id!.GetValue<string>()))],
                arguments["detach"]?.GetValue<bool>() == true)],
            "split.join" => [new JoinSplit(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("tabId"), Argument("targetId"),
                arguments["index"]?.GetValue<int>())],
            "split.title" => [new NameSplit(workspace, Id("spaceId"), Argument("groupId"), arguments["value"]?.GetValue<string>())],
            "split.tint" => [new TintSplit(workspace, Id("spaceId"), Argument("groupId"), Color(arguments["value"]))],
            "space.identity" => [new SetSpaceIdentity(workspace, Id("spaceId"), Text("name"), Text("symbol"),
                SpaceAccent.Named(Text("accent"))!)],
            "space.saved_expansion" => [new ExpandSavedTabs(workspace, Id("spaceId"), arguments["value"]!.GetValue<bool>())],
            "space.branding" => [new SetSpaceBranding(workspace, Id("spaceId"), StoredSessionCodec.DecodeBranding(arguments["value"]))],
            "space.credential_preferences" => [new SetCredentialPreferences(workspace, Id("spaceId"),
                StoredSessionCodec.DecodeCredentialPreferences(arguments["value"]))],
            "space.access" => [new SetSpaceAccess(workspace, Id("spaceId"), StoredSessionCodec.ParseAccessPolicy(Text("value"))!.Value)],
            "space.default" => [new SetDefaultSpace(workspace, Id("spaceId"))],
            "space.reorder" => [new ReorderSpaces(workspace, Moved([.. current.Spaces.Select(space => space.Id)],
                [.. arguments["offsets"]!.AsArray().Select(offset => offset!.GetValue<int>())], arguments["destination"]!.GetValue<int>()))],
            "space.create" => Created(workspace, window ?? Guid.Empty, StoredSessionCodec.DecodeSpace(arguments["template"]), current),
            "space.deletion.begin" => [new BeginDeletingSpace(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("operationID"))],
            "space.remove" => [new FinishDeletingSpace(workspace, window ?? Guid.Empty, Id("spaceId"), Argument("operationID"))],
            "preferences.set" => [new SetAppPreferences(workspace, Preferred(current.AppPreferences ?? AppPreferences.Default,
                Text("preference"), arguments["value"]!))],
            "preferences.translation_rule" => [new SetTranslationRule(workspace, Text("sourceID"), Text("targetID"),
                arguments["isEnabled"]!.GetValue<bool>())],
            "preferences.import" => [new ImportAppPreferences(workspace, Legacy(arguments["legacy"]!.AsObject()))],
            "space.browsing_preferences" => Browsing(workspace, Id("spaceId"), StoredSessionCodec.DecodeBrowsingPreferences(arguments["value"])),
            "space.search_provider.upsert" => Upserted(workspace, Id("spaceId"), arguments),
            "space.search_provider.remove" => [new RemoveSearchProvider(Argument("id"))],
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

    /// Sends the intents a recorded request became, from `window`, while pages
    /// `engine` hosts there show what the request observed its tabs' pages
    /// showing, as a split join's copies start from them, and answers the
    /// changes the core published, through the pages' release.
    public static IReadOnlyList<Change> Send(CrestApp app, Engine engine, JsonObject request, IReadOnlyList<Intent> intents,
        Guid? window) {
        var changes = new List<Change>();
        var shown = new List<Guid>();
        foreach (var observed in request["arguments"]?["copyObservations"] as JsonArray ?? []) {
            var page = Guid.NewGuid();
            changes.AddRange(app.Send(new OpenPage(page, intents.OfType<SessionIntent>().First().WorkspaceId,
                Guid.Parse(request["spaceId"]!.GetValue<string>()),
                Guid.Parse(observed!["tabId"]!.GetValue<string>()), window!.Value)));
            app.Report(engine, new PageCreated(page));
            var snapshot = PageSnapshot.Blank with { Url = observed["url"]?.GetValue<string>(), Title = observed["title"]!.GetValue<string>() };
            app.Report(engine, new PageStateChanged(page, snapshot));
            shown.Add(page);
        }
        foreach (var intent in intents) {
            // The platform erases a Space's profile data before its deletion finishes.
            if (intent is FinishDeletingSpace finishing
                && app.Workspace(finishing.WorkspaceId).Current.Spaces.FirstOrDefault(space => space.Id == finishing.SpaceId) is { } space)
                changes.AddRange(app.Send(new DeleteProfileData(Guid.NewGuid(), space.ProfileId, Ephemeral: false)));
            changes.AddRange(app.Send(intent));
        }
        foreach (var page in shown) changes.AddRange(app.Send(new ReleasePage(page, KeepsState: false)));
        return changes;
    }

    /// An engine for recorded navigations' pages, which does what the core
    /// asks and erases what it is asked to at once.
    public static Engine PageEngine(CrestApp app) {
        Engine? engine = null;
        engine = app.RegisterEngine(new EngineRegistration(EngineKind.WebKit, EngineCapability.Required, IsDefault: true), command => {
            if (command is EraseProfileData erasing) app.Report(engine!, new DataErased(erasing.ErasureId, Erased: true));
        });
        return engine;
    }

    /// Reports `navigation` from a page `engine` hosts in `window` for no tab,
    /// as a Quick Window's page does, and answers the changes the core
    /// published, through the page's release.
    public static IReadOnlyList<Change> Report(CrestApp app, Engine engine, RecordedNavigation navigation, Guid workspace, Guid window) {
        var page = Guid.NewGuid();
        var changes = new List<Change>(app.Send(new OpenPage(page, workspace, navigation.SpaceId, null, window)));
        app.Report(engine, new PageCreated(page));
        app.Report(engine, new NavigationStarted(page, navigation.Url, SameDocument: false));
        app.Report(engine, new NavigationCommitted(page, navigation.Url, SameDocument: false));
        app.Report(engine, new NavigationFinished(page, navigation.Url, navigation.Title));
        changes.AddRange(app.Send(new ReleasePage(page, KeepsState: false)));
        return changes;
    }

    /// The query a recorded `launch.plan` read became, or null for any other
    /// request. Whether setup held the launch back is the device's to say now,
    /// from whether it completed setup, which `SetupCompleted` answers.
    public static LaunchPlan? LaunchPlan(JsonObject request, Guid workspace) {
        if (request["operation"]!.GetValue<string>() != "launch.plan") return null;
        var environment = request["environment"]!.AsObject();
        bool Flag(string key) => environment[key]!.GetValue<bool>();
        return new(workspace, DevicePlatform.Named(request["platform"]!.GetValue<string>())!, new(Flag("testRuntime"),
            Flag("previewRuntime"), Flag("isolatedSession"), Flag("namedProfile"), Flag("isolatedCloudSync"), Flag("resetSession"),
            Flag("showcase"), Flag("inMemoryCredentials"), Flag("onboardingWelcome"), Flag("desktopSetup"), Flag("mobileSetup"),
            Flag("performanceHarness"), Flag("updateTestFeed")));
    }

    /// Whether the device a recorded `launch.plan` read asked about had
    /// completed setup: it had unless setup held that launch back.
    public static bool SetupCompleted(JsonObject request) => !request["hasActiveLaunchGate"]!.GetValue<bool>();

    /// A launch plan in the spelling the recorded answers compare against.
    public static JsonObject Encode(LaunchDecision plan) => new() {
        ["requiresIsolation"] = plan.RequiresIsolation,
        ["usesEphemeralProfileStorage"] = plan.UsesEphemeralProfileStorage,
        ["presentsInstalledApplicationUI"] = plan.PresentsInstalledApplicationUI,
        ["startupBehavior"] = plan.Startup.Name
    };

    /// `current` with the one preference a recorded `preferences.set` named
    /// set to the value it recorded, in its stored spelling.
    private static AppPreferences Preferred(AppPreferences current, string preference, JsonNode value) => preference switch {
        "checksSpelling" => current with { ChecksSpelling = value.GetValue<bool>() },
        "startupBehavior" => current with { Startup = StoredSessionCodec.ParseStartupBehavior(value)! },
        "savedTabClosePolicy" => current with { SavedTabClose = StoredSessionCodec.ParseSavedTabClosePolicy(value)! },
        _ => throw new ArgumentOutOfRangeException(nameof(preference), preference, "The recording sets no other preference.")
    };

    /// The legacy preferences a recorded import carried.
    private static LegacyAppPreferences Legacy(JsonObject legacy) => new(legacy["startupBehavior"]?.GetValue<string>(),
        legacy["offersTranslation"]?.GetValue<bool>(), legacy["automaticallyTranslates"]?.GetValue<bool>(),
        legacy["translationRules"]?.GetValue<string>(), legacy["checksSpelling"]?.GetValue<bool>(),
        legacy["automaticallyEntersPictureInPicture"]?.GetValue<bool>(), legacy["savedTabClosePolicy"]?.GetValue<string>(),
        legacy["savedTabFaviconReturnsToSavedURL"]?.GetValue<bool>(), legacy["splitFocusFollowsMouse"]?.GetValue<bool>());

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
        new SetSpaceIdentity(workspace, template.Id, $"Space {current.Spaces.Count + 1}", template.Settings.Symbol, template.Settings.Accent),
        new SetSpaceBranding(workspace, template.Id, template.Settings.Branding!),
        new SetCredentialPreferences(workspace, template.Id, template.Settings.CredentialPreferences),
        .. Browsing(workspace, template.Id, template.Settings.BrowsingPreferences)
    ];

    /// Recorded browsing preferences, which carried the search choice beside
    /// the rest: the preferences, then what the Space searches with and
    /// whether it suggests.
    private static IReadOnlyList<SessionIntent> Browsing(Guid workspace, Guid space, BrowsingPreferences preferences) => [
        new SetBrowsingPreferences(workspace, space, preferences.CurrentTabCleanup, preferences.ContentBlocking, preferences.DataRetention),
        new SetSpaceSearch(workspace, space, preferences.FollowsDefaultSearch ? null
                : preferences.SelectedCustomEngineId is { } custom ? Named(SearchProvider.CustomName(custom))
                : SearchCatalog.Starting(language: null, region: null).Resolving(preferences.SelectedBuiltInEngine ?? BuiltInSearchProvider.Google),
            preferences.FollowsDefaultSuggestions ? null : preferences.SearchSuggestionsEnabled)
    ];

    /// A recorded upsert of a Space's engine, which the device's catalog now
    /// keeps, and which the Space then searched with when it asked to.
    private static IReadOnlyList<Intent> Upserted(Guid workspace, Guid space, JsonObject arguments) {
        var provider = arguments["provider"]!;
        var engine = CustomSearchProvider.Carried(Guid.Parse(provider["id"]!.GetValue<string>()), provider["name"]!.GetValue<string>(),
            provider["searchURLTemplate"]!.GetValue<string>(), provider["suggestionURLTemplate"]?.GetValue<string>());
        return arguments["selects"]?.GetValue<bool>() == true
            ? [new SaveSearchProvider(engine), new SetSpaceSearch(workspace, space, Named(SearchProvider.CustomName(engine.Id)), null)]
            : [new SaveSearchProvider(engine)];
    }

    /// A provider by the name the device's catalog looks it up by.
    private static SearchProvider Named(string name) =>
        new(name, name, SearchProviderKind.Engine, [], "https://example.com/?q=%s", null, new BrandColor(0, 0, 0), null, null, null);

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
