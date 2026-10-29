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
        Execute("DROP TABLE IF EXISTS device_site_engine");
        Execute("DROP TABLE IF EXISTS device_shortcut");
        Execute("DROP TABLE IF EXISTS device_link");
        Execute("DROP TABLE IF EXISTS device_link_route");
        Execute("DROP TABLE IF EXISTS device_link_site");
        Execute("DROP TABLE IF EXISTS device_link_behavior");
        Execute("CREATE TABLE IF NOT EXISTS device_cloud_transport (id INTEGER PRIMARY KEY CHECK (id = 0), "
            + "record_schema INTEGER NOT NULL, requires_full_pull INTEGER NOT NULL, awaits_account_decision INTEGER NOT NULL, "
            + "overwrites_cloud INTEGER NOT NULL, engine_state BLOB)");
        Execute("CREATE TABLE IF NOT EXISTS device_cloud_record (name TEXT PRIMARY KEY, fields BLOB NOT NULL, schema_version INTEGER)");
        Execute("DROP TABLE IF EXISTS device_palette");
        Execute("DROP TABLE IF EXISTS device_search_catalog");
        Execute("DROP TABLE IF EXISTS device_tab_group");

    }

    /// Everything the device store holds. A row whose identities or names do
    /// not read is left out.
    public DeviceRecords ReadDevice() => new(ReadWindows(), ReadReopening(),
        ReadAdoptions());

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
        if (written is null || !records.Adopted.SetEquals(written.Adopted)) WriteAdoptions(records.Adopted);
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
        InsertInOrder("INSERT INTO device_window_reopen(id, position) VALUES(?,?)", windows, (statement, window, index) => {
            Bind(statement, 1, Spelling(window));
            Checked(Sqlite.sqlite3_bind_int64(statement, 2, index));
        });
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

    /// Inserts one row per item of `items` with `sql`, each bound by `bind`
    /// with the item and its position in the list.
    private void InsertInOrder<T>(string sql, IReadOnlyList<T> items, Action<nint, T, int> bind) {
        for (int position = 0; position < items.Count; position++) {
            var item = items[position];
            int index = position;
            Insert(sql, statement => bind(statement, item, index));
        }
    }

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
