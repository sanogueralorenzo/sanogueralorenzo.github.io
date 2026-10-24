using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// One connection to a session file and its `checkpoint(part, data)` table.
/// Not thread-safe: its owner serializes every call.
internal sealed class SqliteConnection : IDisposable {
    #region Variables

    /// A part is never empty and never larger than a session input may be.
    public const int MaximumPartBytes = NativeSessionAuthority.MaximumBytes;

    private const int BusyTimeoutMilliseconds = 2000;

    private nint handle;

    #endregion

    #region Constructors

    private SqliteConnection(nint handle) => this.handle = handle;

    /// Opens `source` with SQLite's `flags`; a URI source needs `Sqlite.OpenUri`.
    public static SqliteConnection Open(string source, int flags) {
        int result = Sqlite.sqlite3_open_v2(source, out var handle, flags | Sqlite.OpenFullMutex, null);
        if (result != Sqlite.Ok) {
            string message = handle != 0 ? Sqlite.Message(handle) : "";
            if (handle != 0) Sqlite.sqlite3_close_v2(handle);
            throw new StorageException(SqliteFailure.ReasonFor(result), $"Cannot open {source}: {message} ({result})");
        }
        var connection = new SqliteConnection(handle);
        Sqlite.sqlite3_busy_timeout(handle, BusyTimeoutMilliseconds);
        return connection;
    }

    #endregion

    #region Actions - Statements

    public void Execute(string sql) {
        int result = Sqlite.sqlite3_exec(handle, sql, 0, 0, 0);
        if (result != Sqlite.Ok) throw Failure(result);
    }

    /// Runs `body` inside `BEGIN IMMEDIATE … COMMIT`; any failure rolls back.
    public void InTransaction(Action body) {
        Execute("BEGIN IMMEDIATE");
        try {
            body();
            Execute("COMMIT");
        } catch {
            try { Execute("ROLLBACK"); } catch (StorageException) { }
            throw;
        }
    }

    /// The storage version the file records in `PRAGMA user_version`.
    public int ReadUserVersion() => Query("PRAGMA user_version", statement => {
        if (Sqlite.sqlite3_step(statement) != Sqlite.Row) throw Failure(Sqlite.sqlite3_extended_errcode(handle));
        return Sqlite.sqlite3_column_int(statement, 0);
    });

    private T Query<T>(string sql, Func<nint, T> body) {
        int prepared = Sqlite.sqlite3_prepare_v2(handle, sql, -1, out var statement, 0);
        if (prepared != Sqlite.Ok) throw Failure(prepared);
        try { return body(statement); } finally { Sqlite.sqlite3_finalize(statement); }
    }

    private StorageException Failure(int result) =>
        new(SqliteFailure.ReasonFor(result), $"{Sqlite.Message(handle)} ({result})");

    #endregion

    #region Actions - Parts

    /// A part's bytes, or null when the table does not hold it.
    public byte[]? Read(string part) => Query("SELECT data FROM checkpoint WHERE part=?", statement => {
        Bind(statement, part);
        int result = Sqlite.sqlite3_step(statement);
        if (result == Sqlite.Done) return null;
        if (result != Sqlite.Row) throw Failure(result);
        var data = Sqlite.ColumnBlob(statement, 0);
        return data.Length is > 0 and <= MaximumPartBytes
            ? data : throw new StorageException(StorageFailure.Damaged, $"The stored part {part} is empty or too large.");
    });

    /// Every part the table holds.
    public IReadOnlyList<string> Parts() => Query("SELECT part FROM checkpoint", statement => {
        var parts = new List<string>();
        while (true) {
            int result = Sqlite.sqlite3_step(statement);
            if (result == Sqlite.Done) return parts;
            if (result != Sqlite.Row) throw Failure(result);
            parts.Add(Sqlite.ColumnText(statement, 0));
        }
    });

    public void Write(string part, byte[] data) {
        if (data.Length is 0 or > MaximumPartBytes)
            throw new StorageException(StorageFailure.Unavailable, $"The part {part} is empty or too large to store.");
        Query("INSERT INTO checkpoint(part,data) VALUES(?,?) ON CONFLICT(part) DO UPDATE SET data=excluded.data", statement => {
            Bind(statement, part);
            int bound = Sqlite.BindBlob(statement, 2, data);
            if (bound != Sqlite.Ok) throw Failure(bound);
            int result = Sqlite.sqlite3_step(statement);
            return result == Sqlite.Done ? result : throw Failure(result);
        });
    }

    public void Remove(string part) => Query("DELETE FROM checkpoint WHERE part=?", statement => {
        Bind(statement, part);
        int result = Sqlite.sqlite3_step(statement);
        return result == Sqlite.Done ? result : throw Failure(result);
    });

    private void Bind(nint statement, string part) => Bind(statement, 1, part);

    #endregion

    #region Actions - Device store

    /// Creates the device store's tables beside the checkpoint table. They are
    /// additive: a build that predates them reads the file as before.
    /// `device_marker` holds the adoptions an older build knows, which it
    /// rewrites; `device_adoption` holds every adoption, and no older build
    /// touches it.
    public void CreateDeviceTables() {
        Execute("CREATE TABLE IF NOT EXISTS device_window (id TEXT PRIMARY KEY, shown_space TEXT NOT NULL, used INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_window_tab (window TEXT NOT NULL, space TEXT NOT NULL, tab TEXT, "
            + "PRIMARY KEY (window, space))");
        Execute("CREATE TABLE IF NOT EXISTS device_window_split (window TEXT NOT NULL, split_group TEXT NOT NULL, "
            + "position INTEGER NOT NULL, share REAL NOT NULL, PRIMARY KEY (window, split_group, position))");
        Execute("CREATE TABLE IF NOT EXISTS device_window_reopen (id TEXT PRIMARY KEY, position INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_marker (name TEXT PRIMARY KEY)");
        Execute("CREATE TABLE IF NOT EXISTS device_adoption (name TEXT PRIMARY KEY)");
        Execute("CREATE TABLE IF NOT EXISTS device_site_permission (id TEXT PRIMARY KEY, space TEXT NOT NULL, scheme TEXT NOT NULL, "
            + "host TEXT NOT NULL, port INTEGER NOT NULL, permission TEXT NOT NULL, detail TEXT, decision TEXT NOT NULL, "
            + "modified_at REAL NOT NULL, position INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_site_engine (scheme TEXT NOT NULL, host TEXT NOT NULL, port INTEGER NOT NULL, "
            + "engine TEXT NOT NULL, position INTEGER NOT NULL, PRIMARY KEY (scheme, host, port))");
        Execute("CREATE TABLE IF NOT EXISTS device_engine (id INTEGER PRIMARY KEY CHECK (id = 0), engine TEXT NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_shortcut (command TEXT PRIMARY KEY, key TEXT, special INTEGER NOT NULL, "
            + "modifiers INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_link (id INTEGER PRIMARY KEY CHECK (id = 0), destination TEXT NOT NULL, "
            + "destination_space TEXT, peek_modifier TEXT NOT NULL, archive_policy TEXT NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_link_behavior (name TEXT PRIMARY KEY, is_on INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_link_route (id TEXT PRIMARY KEY, enabled INTEGER NOT NULL, match TEXT NOT NULL, "
            + "pattern TEXT NOT NULL, space TEXT NOT NULL, position INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_link_site (site TEXT PRIMARY KEY, space TEXT NOT NULL, position INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_cloud_transport (id INTEGER PRIMARY KEY CHECK (id = 0), "
            + "record_schema INTEGER NOT NULL, requires_full_pull INTEGER NOT NULL, awaits_account_decision INTEGER NOT NULL, "
            + "overwrites_cloud INTEGER NOT NULL, engine_state BLOB)");
        Execute("CREATE TABLE IF NOT EXISTS device_cloud_record (name TEXT PRIMARY KEY, fields BLOB NOT NULL, schema_version INTEGER)");
        Execute("CREATE TABLE IF NOT EXISTS device_setup_draft (id INTEGER PRIMARY KEY CHECK (id = 0), document TEXT NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_palette (space TEXT PRIMARY KEY, document TEXT NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_search_catalog (id INTEGER PRIMARY KEY CHECK (id = 0), document TEXT NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_setup (id INTEGER PRIMARY KEY CHECK (id = 0), completed INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_tab_group (id TEXT PRIMARY KEY, space TEXT NOT NULL, engine TEXT NOT NULL, "
            + "title TEXT NOT NULL, color TEXT NOT NULL, position INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_agents (id INTEGER PRIMARY KEY CHECK (id = 0), is_on INTEGER NOT NULL, "
            + "runs_scripts INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_agent_space (space TEXT PRIMARY KEY, position INTEGER NOT NULL)");
        Execute("CREATE TABLE IF NOT EXISTS device_agent (position INTEGER PRIMARY KEY, team TEXT, signing TEXT, path TEXT, "
            + "client TEXT, name TEXT NOT NULL)");
    }

    /// Everything the device store holds. A row whose identities or names do
    /// not read is left out.
    public DeviceRecords ReadDevice() => new(ReadWindows(), ReadReopening(), ReadSitePermissions(), ReadSiteEngines(), ReadShortcuts(),
        ReadLinks(), ReadSetupDraft(), ReadSetupCompleted(), ReadAdoptions(), ReadTabGroups(), ReadDefaultEngine()) {
        PaletteMemories = ReadPaletteMemories(),
        SearchCatalog = ReadSearchCatalog(),
        Agents = ReadAgents()
    };

    /// The search catalog the store keeps, or null when it keeps none or it does not read.
    private SearchCatalog? ReadSearchCatalog() {
        string? document = null;
        Rows("SELECT document FROM device_search_catalog", statement => document = Sqlite.ColumnText(statement, 0));
        return SearchCatalogDocument.Read(document);
    }

    /// Each persistent Space's palette memory that reads, by Space.
    private Dictionary<Guid, PaletteMemory> ReadPaletteMemories() {
        var memories = new Dictionary<Guid, PaletteMemory>();
        Rows("SELECT space, document FROM device_palette", statement => {
            if (Identity(statement, 0) is { } space && PaletteMemoryDocument.Read(Sqlite.ColumnText(statement, 1)) is { } memory)
                memories[space] = memory;
        });
        return memories;
    }

    /// The person's preference remains available even in a single-engine product.
    private EngineKind? ReadDefaultEngine() {
        EngineKind? engine = null;
        Rows("SELECT engine FROM device_engine WHERE id = 0", statement => engine = EngineKind.Named(Sqlite.ColumnText(statement, 0)));
        return engine;
    }

    private List<SavedWindow> ReadWindows() {
        var windows = new Dictionary<Guid, (Guid ShownSpace, long Used)>();
        var tabs = new List<(Guid Window, ShownTab Tab)>();
        var shares = new List<(Guid Window, Guid Group, double Share)>();
        Rows("SELECT id, shown_space, used FROM device_window", statement => {
            if (Identity(statement, 0) is { } id && Identity(statement, 1) is { } shown)
                windows[id] = (shown, Sqlite.sqlite3_column_int64(statement, 2));
        });
        Rows("SELECT window, space, tab FROM device_window_tab", statement => {
            if (Identity(statement, 0) is { } window && Identity(statement, 1) is { } space)
                tabs.Add((window, new ShownTab(space, Sqlite.ColumnIsNull(statement, 2) ? null : Identity(statement, 2))));
        });
        Rows("SELECT window, split_group, share FROM device_window_split ORDER BY window, split_group, position", statement => {
            if (Identity(statement, 0) is { } window && Identity(statement, 1) is { } group)
                shares.Add((window, group, Sqlite.sqlite3_column_double(statement, 2)));
        });
        return [.. windows.Select(window => new SavedWindow(window.Key, window.Value.ShownSpace,
            [.. tabs.Where(tab => tab.Window == window.Key).Select(tab => tab.Tab)],
            [.. shares.Where(share => share.Window == window.Key).GroupBy(share => share.Group)
                .Select(group => new SplitColumnShares(group.Key, [.. group.Select(share => share.Share)]))],
            window.Value.Used)).OrderBy(record => record.Used)];
    }

    /// The saved windows the next launch reopens, back to front.
    private List<Guid> ReadReopening() {
        var windows = new List<Guid>();
        Rows("SELECT id FROM device_window_reopen ORDER BY position", statement => {
            if (Identity(statement, 0) is { } id) windows.Add(id);
        });
        return windows;
    }

    private List<SitePermissionRecord> ReadSitePermissions() {
        var records = new List<SitePermissionRecord>();
        Rows("SELECT id, space, scheme, host, port, permission, detail, decision, modified_at FROM device_site_permission "
            + "ORDER BY position", statement => {
                if (Identity(statement, 0) is not { } id || Identity(statement, 1) is not { } space
                    || SitePermission.Named(Sqlite.ColumnText(statement, 5)) is not { } permission
                    || SitePermissionDecision.Named(Sqlite.ColumnText(statement, 7)) is not { } decision) return;
                records.Add(new(id, space,
                    new SiteOrigin(Sqlite.ColumnText(statement, 2), Sqlite.ColumnText(statement, 3), Sqlite.sqlite3_column_int(statement, 4)),
                    permission, Sqlite.ColumnIsNull(statement, 6) ? null : Sqlite.ColumnText(statement, 6), decision,
                    Sqlite.sqlite3_column_double(statement, 8)));
            });
        return records;
    }

    /// The tab groups whose folders follow them, in storage order. A group a
    /// later release names by an engine or color this one cannot read is left
    /// out.
    private List<TabGroupRecord> ReadTabGroups() {
        var groups = new List<TabGroupRecord>();
        Rows("SELECT id, space, engine, title, color FROM device_tab_group ORDER BY position", statement => {
            if (Identity(statement, 0) is { } id && Identity(statement, 1) is { } space
                && EngineKind.Named(Sqlite.ColumnText(statement, 2)) is { } engine
                && TabGroupColor.Named(Sqlite.ColumnText(statement, 4)) is { } color)
                groups.Add(new(id, space, engine, Sqlite.ColumnText(statement, 3), color));
        });
        return groups;
    }

    /// The site engine choices, least recent first. A row naming an engine
    /// this build does not know is left out.
    private List<SiteEngineChoice> ReadSiteEngines() {
        var choices = new List<SiteEngineChoice>();
        Rows("SELECT scheme, host, port, engine FROM device_site_engine ORDER BY position", statement => {
            if (EngineKind.Named(Sqlite.ColumnText(statement, 3)) is not { } engine) return;
            var origin = new SiteOrigin(Sqlite.ColumnText(statement, 0), Sqlite.ColumnText(statement, 1),
                Sqlite.sqlite3_column_int(statement, 2));
            if (origin.IsValid) choices.Add(new(null, origin, engine));
        });
        return choices;
    }

    /// Each command's choice: no key is a command left without one.
    private ShortcutOverrides ReadShortcuts() {
        var choices = new List<KeyValuePair<string, ShortcutChord?>>();
        Rows("SELECT command, key, special, modifiers FROM device_shortcut ORDER BY command", statement => {
            string command = Sqlite.ColumnText(statement, 0);
            if (Sqlite.ColumnIsNull(statement, 1)) {
                choices.Add(new(command, null));
                return;
            }
            string key = Sqlite.ColumnText(statement, 1);
            int modifiers = Sqlite.sqlite3_column_int(statement, 3);
            bool special = Sqlite.sqlite3_column_int(statement, 2) != 0;
            if (special ? ShortcutSpecialKey.Named(key) is null : key.Length is 0 or > ShortcutChord.MaximumCharacterLength) return;
            choices.Add(new(command, special ? ShortcutChord.Special(key, modifiers) : ShortcutChord.Character(key, modifiers)));
        });
        return ShortcutOverrides.Restore(choices);
    }

    /// The link preferences, each value that does not read keeping its
    /// default: a device that never chose any holds no rows.
    private LinkPreferences ReadLinks() {
        var links = LinkPreferences.Default;
        Rows("SELECT destination, destination_space, peek_modifier, archive_policy FROM device_link", statement => links = links with {
            Destination = ExternalLinkDestination.Named(Sqlite.ColumnText(statement, 0)) ?? links.Destination,
            DestinationSpaceId = Identity(statement, 1),
            PeekModifier = LinkPeekModifier.Named(Sqlite.ColumnText(statement, 2)) ?? links.PeekModifier,
            ArchivePolicy = QuickWindowArchivePolicy.Named(Sqlite.ColumnText(statement, 3)) ?? links.ArchivePolicy
        });
        Rows("SELECT name, is_on FROM device_link_behavior", statement => {
            if (LinkBehavior.Named(Sqlite.ColumnText(statement, 0)) is { } behavior)
                links = behavior.Setting(links, Sqlite.sqlite3_column_int(statement, 1) != 0);
        });
        var routes = new List<LinkRoute>();
        Rows("SELECT id, enabled, match, pattern, space FROM device_link_route ORDER BY position", statement => {
            if (Identity(statement, 0) is { } id && LinkRouteMatch.Named(Sqlite.ColumnText(statement, 2)) is { } match
                && Identity(statement, 4) is { } space)
                routes.Add(new(id, Sqlite.sqlite3_column_int(statement, 1) != 0, match, Sqlite.ColumnText(statement, 3), space));
        });
        var sites = new List<RememberedSite>();
        Rows("SELECT site, space FROM device_link_site ORDER BY position", statement => {
            if (Identity(statement, 1) is { } space) sites.Add(new(Sqlite.ColumnText(statement, 0), space));
        });
        return links with { Routes = routes, RememberedSites = sites };
    }

    /// The agent preferences: off, reaching nothing and trusting no agent for a
    /// device that never chose any. A Space or agent that does not read is
    /// left out.
    private AgentPreferences ReadAgents() {
        bool isOn = false;
        bool runsScripts = false;
        Rows("SELECT is_on, runs_scripts FROM device_agents", statement => {
            isOn = Sqlite.sqlite3_column_int(statement, 0) != 0;
            runsScripts = Sqlite.sqlite3_column_int(statement, 1) != 0;
        });
        var spaces = new List<Guid>();
        Rows("SELECT space FROM device_agent_space ORDER BY position", statement => {
            if (Identity(statement, 0) is { } space) spaces.Add(space);
        });
        var approved = new List<ApprovedAgent>();
        static string? Optional(nint statement, int column) =>
            Sqlite.ColumnIsNull(statement, column) ? null : Sqlite.ColumnText(statement, column);
        Rows("SELECT team, signing, path, client, name FROM device_agent ORDER BY position", statement => {
            var identity = new AgentIdentity(Optional(statement, 0), Optional(statement, 1), Optional(statement, 2),
                Optional(statement, 3));
            if (identity.IsValid && AgentPreferences.CleanName(Sqlite.ColumnText(statement, 4)) is { } name)
                approved.Add(new ApprovedAgent(identity, name));
        });
        return new(isOn, runsScripts, spaces, approved);
    }

    /// The unfinished manual setup, or null when the store keeps none or it
    /// does not read.
    private KeptSetupDraft? ReadSetupDraft() {
        string? document = null;
        Rows("SELECT document FROM device_setup_draft", statement => document = Sqlite.ColumnText(statement, 0));
        return KeptSetupDraft.Read(document);
    }

    /// Whether this device has completed setup: never, until the store says so.
    private bool ReadSetupCompleted() {
        bool completed = false;
        Rows("SELECT completed FROM device_setup", statement => completed = Sqlite.sqlite3_column_int(statement, 0) != 0);
        return completed;
    }

    private HashSet<DeviceAdoption> ReadAdoptions() {
        var adoptions = new HashSet<DeviceAdoption>();
        foreach (var table in new[] { "device_marker", "device_adoption" })
            Rows($"SELECT name FROM {table}", statement => {
                if (DeviceAdoption.Marked(Sqlite.ColumnText(statement, 0)) is { } adoption) adoptions.Add(adoption);
            });
        return adoptions;
    }

    /// Writes `records` over what the device store holds, rewriting only the
    /// parts that differ from `written`, which the store holds now; with null,
    /// every part. The caller runs it inside a transaction.
    public void WriteDevice(DeviceRecords records, DeviceRecords? written) {
        if (written is null || !records.Windows.SequenceEqual(written.Windows)) WriteWindows(records.Windows);
        if (written is null || !records.Reopening.SequenceEqual(written.Reopening)) WriteReopening(records.Reopening);
        if (written is null || !records.SitePermissions.SequenceEqual(written.SitePermissions)) WriteSitePermissions(records.SitePermissions);
        if (written is null || !records.SiteEngines.SequenceEqual(written.SiteEngines)) WriteSiteEngines(records.SiteEngines);
        if (written is null || records.DefaultEngine != written.DefaultEngine) WriteDefaultEngine(records.DefaultEngine);
        if (written is null || !records.Shortcuts.SameAs(written.Shortcuts)) WriteShortcuts(records.Shortcuts);
        if (written is null || !records.Links.Equals(written.Links)) WriteLinks(records.Links);
        if (written is null || !KeptSetupDraft.Same(records.SetupDraft, written.SetupDraft)) WriteSetupDraft(records.SetupDraft);
        if (written is null || records.SetupCompleted != written.SetupCompleted) WriteSetupCompleted(records.SetupCompleted);
        if (written is null || !records.Adopted.SetEquals(written.Adopted)) WriteAdoptions(records.Adopted);
        if (written is null || !records.TabGroups.SequenceEqual(written.TabGroups)) WriteTabGroups(records.TabGroups);
        WritePaletteMemories(records.PaletteMemories, written?.PaletteMemories);
        if (written is null || !ReferenceEquals(records.SearchCatalog, written.SearchCatalog)) WriteSearchCatalog(records.SearchCatalog);
        if (written is null || !records.Agents.Equals(written.Agents)) WriteAgents(records.Agents);
    }

    /// The search catalog as its one document, or no row before it was first restored.
    private void WriteSearchCatalog(SearchCatalog? catalog) {
        Execute("DELETE FROM device_search_catalog");
        if (catalog is null) return;
        Insert("INSERT INTO device_search_catalog(id, document) VALUES(0,?)",
            statement => Bind(statement, 1, SearchCatalogDocument.Write(catalog)));
    }

    /// Each Space's palette memory that differs from what was written, and no
    /// row for a Space whose memory went.
    private void WritePaletteMemories(IReadOnlyDictionary<Guid, PaletteMemory> memories, IReadOnlyDictionary<Guid, PaletteMemory>? written) {
        if (written is null) Execute("DELETE FROM device_palette");
        foreach (var gone in written?.Keys.Where(space => !memories.ContainsKey(space)) ?? [])
            Insert("DELETE FROM device_palette WHERE space = ?", statement => Bind(statement, 1, Spelling(gone)));
        foreach (var (space, memory) in memories) {
            if (written is not null && written.TryGetValue(space, out var kept) && ReferenceEquals(kept, memory)) continue;
            Insert("INSERT OR REPLACE INTO device_palette(space, document) VALUES(?,?)", statement => {
                Bind(statement, 1, Spelling(space));
                Bind(statement, 2, PaletteMemoryDocument.Write(memory));
            });
        }
    }

    /// The agent preferences: whether they are on and run scripts in pages,
    /// and the allowed Spaces and approved agents in order.
    private void WriteAgents(AgentPreferences preferences) {
        foreach (var table in new[] { "device_agents", "device_agent_space", "device_agent" })
            Execute($"DELETE FROM {table}");
        Insert("INSERT INTO device_agents(id, is_on, runs_scripts) VALUES(0,?,?)", statement => {
            Checked(Sqlite.sqlite3_bind_int64(statement, 1, preferences.IsOn ? 1 : 0));
            Checked(Sqlite.sqlite3_bind_int64(statement, 2, preferences.RunsScripts ? 1 : 0));
        });
        for (int position = 0; position < preferences.SpaceIds.Count; position++) {
            var space = preferences.SpaceIds[position];
            int index = position;
            Insert("INSERT INTO device_agent_space(space, position) VALUES(?,?)", statement => {
                Bind(statement, 1, Spelling(space));
                Checked(Sqlite.sqlite3_bind_int64(statement, 2, index));
            });
        }
        for (int position = 0; position < preferences.Agents.Count; position++) {
            var agent = preferences.Agents[position];
            int index = position;
            Insert("INSERT INTO device_agent(position, team, signing, path, client, name) VALUES(?,?,?,?,?,?)", statement => {
                Checked(Sqlite.sqlite3_bind_int64(statement, 1, index));
                Bind(statement, 2, agent.Identity.TeamId);
                Bind(statement, 3, agent.Identity.SigningId);
                Bind(statement, 4, agent.Identity.Path);
                Bind(statement, 5, agent.Identity.Client);
                Bind(statement, 6, agent.Name);
            });
        }
    }

    /// The tab groups in order, each engine and color by its `Name`.
    private void WriteTabGroups(IReadOnlyList<TabGroupRecord> groups) {
        Execute("DELETE FROM device_tab_group");
        for (int position = 0; position < groups.Count; position++) {
            var group = groups[position];
            int index = position;
            Insert("INSERT INTO device_tab_group(id, space, engine, title, color, position) VALUES(?,?,?,?,?,?)", statement => {
                Bind(statement, 1, Spelling(group.Id));
                Bind(statement, 2, Spelling(group.SpaceId));
                Bind(statement, 3, group.Engine.Name);
                Bind(statement, 4, group.Title);
                Bind(statement, 5, group.Color.Name);
                Checked(Sqlite.sqlite3_bind_int64(statement, 6, index));
            });
        }
    }

    private void WriteWindows(IReadOnlyList<SavedWindow> windows) {
        foreach (var table in new[] { "device_window", "device_window_tab", "device_window_split" }) Execute($"DELETE FROM {table}");
        foreach (var window in windows) {
            Insert("INSERT INTO device_window(id, shown_space, used) VALUES(?,?,?)", statement => {
                Bind(statement, 1, Spelling(window.Id));
                Bind(statement, 2, Spelling(window.ShownSpaceId));
                Checked(Sqlite.sqlite3_bind_int64(statement, 3, window.Used));
            });
            foreach (var tab in window.Tabs)
                Insert("INSERT INTO device_window_tab(window, space, tab) VALUES(?,?,?)", statement => {
                    Bind(statement, 1, Spelling(window.Id));
                    Bind(statement, 2, Spelling(tab.SpaceId));
                    Bind(statement, 3, tab.TabId is { } id ? Spelling(id) : null);
                });
            foreach (var group in window.Shares)
                for (int position = 0; position < group.Shares.Count; position++) {
                    int column = position;
                    Insert("INSERT INTO device_window_split(window, split_group, position, share) VALUES(?,?,?,?)", statement => {
                        Bind(statement, 1, Spelling(window.Id));
                        Bind(statement, 2, Spelling(group.GroupId));
                        Checked(Sqlite.sqlite3_bind_int64(statement, 3, column));
                        Checked(Sqlite.sqlite3_bind_double(statement, 4, group.Shares[column]));
                    });
                }
        }
    }

    /// The saved windows the next launch reopens, in order, back to front.
    private void WriteReopening(IReadOnlyList<Guid> windows) {
        Execute("DELETE FROM device_window_reopen");
        for (int position = 0; position < windows.Count; position++) {
            var window = windows[position];
            int index = position;
            Insert("INSERT INTO device_window_reopen(id, position) VALUES(?,?)", statement => {
                Bind(statement, 1, Spelling(window));
                Checked(Sqlite.sqlite3_bind_int64(statement, 2, index));
            });
        }
    }

    /// The choices in storage order, with every value exactly as the record
    /// holds it: the capability and decision by `Name`, the time as the double
    /// it was.
    private void WriteSitePermissions(IReadOnlyList<SitePermissionRecord> records) {
        Execute("DELETE FROM device_site_permission");
        for (int position = 0; position < records.Count; position++) {
            var record = records[position];
            int index = position;
            Insert("INSERT INTO device_site_permission(id, space, scheme, host, port, permission, detail, decision, modified_at, position) "
                + "VALUES(?,?,?,?,?,?,?,?,?,?)", statement => {
                    Bind(statement, 1, Spelling(record.Id));
                    Bind(statement, 2, Spelling(record.Space));
                    Bind(statement, 3, record.Origin.Scheme);
                    Bind(statement, 4, record.Origin.Host);
                    Checked(Sqlite.sqlite3_bind_int64(statement, 5, record.Origin.Port));
                    Bind(statement, 6, record.Permission.Name);
                    Bind(statement, 7, record.Detail);
                    Bind(statement, 8, record.Decision.Name);
                    Checked(Sqlite.sqlite3_bind_double(statement, 9, record.ModifiedAt));
                    Checked(Sqlite.sqlite3_bind_int64(statement, 10, index));
                });
        }
    }

    /// The person's explicit default, absent while following the composition.
    private void WriteDefaultEngine(EngineKind? engine) {
        Execute("DELETE FROM device_engine");
        if (engine is not null)
            Insert("INSERT INTO device_engine(id, engine) VALUES(0,?)", statement => Bind(statement, 1, engine.Name));
    }

    /// The site engine choices, least recent first, each engine by `Name`.
    private void WriteSiteEngines(IReadOnlyList<SiteEngineChoice> choices) {
        Execute("DELETE FROM device_site_engine");
        for (int position = 0; position < choices.Count; position++) {
            var choice = choices[position];
            int index = position;
            Insert("INSERT INTO device_site_engine(scheme, host, port, engine, position) VALUES(?,?,?,?,?)", statement => {
                Bind(statement, 1, choice.Origin.Scheme);
                Bind(statement, 2, choice.Origin.Host);
                Checked(Sqlite.sqlite3_bind_int64(statement, 3, choice.Origin.Port));
                Bind(statement, 4, choice.Engine.Name);
                Checked(Sqlite.sqlite3_bind_int64(statement, 5, index));
            });
        }
    }

    /// Each command's choice, with the modifier mask's every bit; a command
    /// left without a chord has no key.
    private void WriteShortcuts(ShortcutOverrides shortcuts) {
        Execute("DELETE FROM device_shortcut");
        foreach (var (command, chord) in shortcuts.Chords)
            Insert("INSERT INTO device_shortcut(command, key, special, modifiers) VALUES(?,?,?,?)", statement => {
                Bind(statement, 1, command);
                Bind(statement, 2, chord?.Key);
                Checked(Sqlite.sqlite3_bind_int64(statement, 3, chord?.IsSpecial == true ? 1 : 0));
                Checked(Sqlite.sqlite3_bind_int64(statement, 4, chord?.Modifiers ?? 0));
            });
    }

    /// The link preferences: the fixed sets by `Name`, each on-or-off
    /// preference under its behavior's `Name`, and the routes and remembered
    /// sites in order.
    private void WriteLinks(LinkPreferences links) {
        foreach (var table in new[] { "device_link", "device_link_behavior", "device_link_route", "device_link_site" })
            Execute($"DELETE FROM {table}");
        Insert("INSERT INTO device_link(id, destination, destination_space, peek_modifier, archive_policy) VALUES(0,?,?,?,?)", statement => {
            Bind(statement, 1, links.Destination.Name);
            Bind(statement, 2, links.DestinationSpaceId is { } space ? Spelling(space) : null);
            Bind(statement, 3, links.PeekModifier.Name);
            Bind(statement, 4, links.ArchivePolicy.Name);
        });
        foreach (var behavior in LinkBehavior.All)
            Insert("INSERT INTO device_link_behavior(name, is_on) VALUES(?,?)", statement => {
                Bind(statement, 1, behavior.Name);
                Checked(Sqlite.sqlite3_bind_int64(statement, 2, behavior.IsOn(links) ? 1 : 0));
            });
        for (int position = 0; position < links.Routes.Count; position++) {
            var route = links.Routes[position];
            int index = position;
            Insert("INSERT INTO device_link_route(id, enabled, match, pattern, space, position) VALUES(?,?,?,?,?,?)", statement => {
                Bind(statement, 1, Spelling(route.Id));
                Checked(Sqlite.sqlite3_bind_int64(statement, 2, route.IsEnabled ? 1 : 0));
                Bind(statement, 3, route.Match.Name);
                Bind(statement, 4, route.Pattern);
                Bind(statement, 5, Spelling(route.DestinationSpaceId));
                Checked(Sqlite.sqlite3_bind_int64(statement, 6, index));
            });
        }
        for (int position = 0; position < links.RememberedSites.Count; position++) {
            var remembered = links.RememberedSites[position];
            int index = position;
            Insert("INSERT INTO device_link_site(site, space, position) VALUES(?,?,?)", statement => {
                Bind(statement, 1, remembered.Site);
                Bind(statement, 2, Spelling(remembered.SpaceId));
                Checked(Sqlite.sqlite3_bind_int64(statement, 3, index));
            });
        }
    }

    /// The unfinished manual setup as its one document, or no row for none.
    private void WriteSetupDraft(KeptSetupDraft? draft) {
        Execute("DELETE FROM device_setup_draft");
        if (draft is null) return;
        Insert("INSERT INTO device_setup_draft(id, document) VALUES(0,?)", statement => Bind(statement, 1, draft.Document));
    }

    private void WriteSetupCompleted(bool completed) {
        Execute("DELETE FROM device_setup");
        Insert("INSERT INTO device_setup(id, completed) VALUES(0,?)", statement => Checked(Sqlite.sqlite3_bind_int64(statement, 1, completed ? 1 : 0)));
    }

    /// Every adoption goes into `device_adoption`; the ones an older build
    /// knows also go into `device_marker`, which that build reads and rewrites.
    /// An adoption is never undone, so the markers are only ever added: a
    /// write of records captured before an adoption another save recorded
    /// keeps its marker.
    private void WriteAdoptions(IReadOnlySet<DeviceAdoption> adoptions) {
        foreach (var adoption in DeviceAdoption.All.Where(adoptions.Contains)) MarkAdopted(adoption);
    }

    /// Records `adoption` as done. The caller runs it inside a transaction.
    public void MarkAdopted(DeviceAdoption adoption) {
        Insert("INSERT OR IGNORE INTO device_adoption(name) VALUES(?)", statement => Bind(statement, 1, adoption.Marker));
        if (adoption.OlderBuildsRead)
            Insert("INSERT OR IGNORE INTO device_marker(name) VALUES(?)", statement => Bind(statement, 1, adoption.Marker));
    }

    #endregion

    #region Actions - Cloud transport

    /// The cloud transport's state the device store keeps, or null while it
    /// keeps none.
    public CloudTransportRecord? ReadCloudTransport() => Query(
        "SELECT record_schema, requires_full_pull, awaits_account_decision, overwrites_cloud, engine_state FROM device_cloud_transport",
        statement => {
            int result = Sqlite.sqlite3_step(statement);
            if (result == Sqlite.Done) return null;
            if (result != Sqlite.Row) throw Failure(result);
            return new CloudTransportRecord(checked((int)Sqlite.sqlite3_column_int64(statement, 0)),
                Sqlite.sqlite3_column_int64(statement, 1) != 0, Sqlite.sqlite3_column_int64(statement, 2) != 0,
                Sqlite.sqlite3_column_int64(statement, 3) != 0, Sqlite.ColumnIsNull(statement, 4) ? null : Sqlite.ColumnBlob(statement, 4));
        });

    /// Writes `record` over the cloud transport's state. The caller runs it
    /// inside a transaction.
    public void WriteCloudTransport(CloudTransportRecord record) {
        Execute("DELETE FROM device_cloud_transport");
        Insert("INSERT INTO device_cloud_transport(id, record_schema, requires_full_pull, awaits_account_decision, overwrites_cloud, "
            + "engine_state) VALUES(0,?,?,?,?,?)", statement => {
                Checked(Sqlite.sqlite3_bind_int64(statement, 1, record.RecordSchema));
                Checked(Sqlite.sqlite3_bind_int64(statement, 2, record.RequiresFullPull ? 1 : 0));
                Checked(Sqlite.sqlite3_bind_int64(statement, 3, record.AwaitsAccountDecision ? 1 : 0));
                Checked(Sqlite.sqlite3_bind_int64(statement, 4, record.OverwritesCloud ? 1 : 0));
                Checked(record.EngineState is { } state ? Sqlite.BindBlob(statement, 5, state) : Sqlite.BindNull(statement, 5));
            });
    }

    /// Forgets every record's server fields when `clearing`, then keeps those
    /// of `updated` and forgets those of `removed`. The caller runs it inside
    /// a transaction.
    public void WriteCloudFields(bool clearing, IReadOnlyList<CloudRecordFields> updated, IReadOnlyList<string> removed) {
        if (clearing) Execute("DELETE FROM device_cloud_record");
        foreach (var name in removed)
            Insert("DELETE FROM device_cloud_record WHERE name=?", statement => Bind(statement, 1, name));
        foreach (var fields in updated)
            Insert("INSERT OR REPLACE INTO device_cloud_record(name, fields, schema_version) VALUES(?,?,?)", statement => {
                Bind(statement, 1, fields.RecordName);
                Checked(Sqlite.BindBlob(statement, 2, fields.Fields));
                Checked(fields.SchemaVersion is { } schema
                    ? Sqlite.sqlite3_bind_int64(statement, 3, schema) : Sqlite.BindNull(statement, 3));
            });
    }

    /// The server fields kept of `names`; a record kept without any is left
    /// out.
    public IReadOnlyList<CloudRecordFields> ReadCloudFields(IReadOnlyList<string> names) {
        var found = new List<CloudRecordFields>();
        foreach (var name in names)
            Query("SELECT fields, schema_version FROM device_cloud_record WHERE name=?", statement => {
                Bind(statement, 1, name);
                int result = Sqlite.sqlite3_step(statement);
                if (result == Sqlite.Done) return result;
                if (result != Sqlite.Row) throw Failure(result);
                found.Add(new(name, Sqlite.ColumnBlob(statement, 0),
                    Sqlite.ColumnIsNull(statement, 1) ? null : checked((int)Sqlite.sqlite3_column_int64(statement, 1))));
                return result;
            });
        return found;
    }

    private void Rows(string sql, Action<nint> row) => Query(sql, statement => {
        while (true) {
            int result = Sqlite.sqlite3_step(statement);
            if (result == Sqlite.Done) return result;
            if (result != Sqlite.Row) throw Failure(result);
            row(statement);
        }
    });

    private void Insert(string sql, Action<nint> bind) => Query(sql, statement => {
        bind(statement);
        int result = Sqlite.sqlite3_step(statement);
        return result == Sqlite.Done ? result : throw Failure(result);
    });

    private void Bind(nint statement, int index, string? value) => Checked(Sqlite.BindText(statement, index, value));

    private void Checked(int result) {
        if (result != Sqlite.Ok) throw Failure(result);
    }

    private static Guid? Identity(nint statement, int column) =>
        Guid.TryParse(Sqlite.ColumnText(statement, column), out var id) ? id : null;

    /// An identity as the store spells it.
    private static string Spelling(Guid id) => id.ToString("D").ToUpperInvariant();

    #endregion

    #region Actions - Backup

    /// Copies every committed page, WAL included, into a new standalone file
    /// at `destination` that has no sidecars.
    public void Backup(string destination) {
        var target = Open(destination, Sqlite.OpenReadWrite | Sqlite.OpenCreate);
        try {
            nint backup = Sqlite.sqlite3_backup_init(target.handle, "main", handle, "main");
            if (backup == 0) throw target.Failure(Sqlite.sqlite3_extended_errcode(target.handle));
            int step = Sqlite.sqlite3_backup_step(backup, -1);
            int finished = Sqlite.sqlite3_backup_finish(backup);
            if (step != Sqlite.Done) throw target.Failure(step);
            if (finished != Sqlite.Ok) throw target.Failure(finished);
            target.Execute("PRAGMA journal_mode=DELETE");
        } finally {
            target.Dispose();
        }
    }

    #endregion

    #region Actions - Lifetime

    public void Dispose() {
        if (handle == 0) return;
        Sqlite.sqlite3_close_v2(handle);
        handle = 0;
    }

    #endregion
}
