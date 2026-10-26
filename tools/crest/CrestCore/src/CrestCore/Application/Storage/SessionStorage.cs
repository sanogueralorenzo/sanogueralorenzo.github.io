using CrestCore.Contracts;

namespace CrestCore.Application;

/// The session file the core owns: `session.sqlite` in the host's storage
/// directory, with the table, part names and pragmas every earlier release
/// used, so a rollback build still reads it.
///
/// One connection writes the file, one writer at a time. Accepted revisions
/// are saved behind by one worker thread, which always writes the newest one
/// and never an older revision over a newer one. Durable saves write on the
/// caller's thread before the revision is published. A journal is always
/// written in one transaction with the newest accepted session, so the
/// journal is never ahead of the session on disk. Parts whose bytes did not
/// change are not rewritten.
///
/// Everything the file is handed to write takes the next file revision: each
/// accepted session revision and each change to this device's saved windows.
/// `PendingRevision` answers the newest one not on disk yet, and `Saved`
/// announces each newer revision up to which everything is on disk.
///
/// The writer lock is never taken while the session gate is held, and changes
/// are announced only after every storage lock is released.
internal sealed class SessionStorage : IDisposable {
    #region Types

    /// The newest value of one kind the file was handed and has not written.
    /// It supersedes every earlier one, so writing it writes them all:
    /// `Revision` is the file revision it was handed at, and `Since` the
    /// oldest file revision of its kind still unwritten.
    private sealed record Unwritten<T>(T Value, ulong Revision, ulong Since) {
        #region Actions - Revisions

        /// `value`, handed at `revision`, in place of `earlier`.
        public static Unwritten<T> Replacing(Unwritten<T>? earlier, T value, ulong revision) =>
            new(value, revision, earlier?.Since ?? revision);

        /// What stays unwritten once the value handed at `written` is on disk:
        /// nothing when that was this one, or this newer one.
        public Unwritten<T>? After(ulong written) =>
            Revision <= written ? null : this with { Since = Math.Max(Since, written + 1) };

        #endregion
    }

    #endregion

    #region Variables

    public const string FileName = "session.sqlite";
    private const string RecoveryFileName = "session.recovery.sqlite";
    private const string RestoreMarkerSuffix = ".restore-pending";
    /// Beside the file while the cloud transport owes a full pull: the file
    /// holds a seed that stands in for an unreadable installed session, or a
    /// restored journal that its newer cursor cannot describe. The transport
    /// removes it once it has opted in.
    private const string CloudRecoverySuffix = ".cloud-recovery";
    private const string PreservedDirectoryPrefix = "Recovery-";
    private const string TemporaryExtension = ".sqlite";
    private static readonly string[] SidecarSuffixes = ["-wal", "-shm"];
    /// The rollback journal SQLite keeps beside a checkpoint copy while it writes.
    private const string RollbackJournalSuffix = "-journal";
    private const int StorageVersion = 1;
    private const UnixFileMode OwnerOnly = UnixFileMode.UserRead | UnixFileMode.UserWrite | UnixFileMode.UserExecute;

    private readonly SqliteConnection connection;
    private readonly Action<Change> announce;
    private readonly Thread worker;
    /// Guards what is unwritten, the revisions handed out and the worker's
    /// wake-up; the worker waits on it.
    private readonly object queue = new();
    /// One writer at a time, and the only owner of the connection.
    private readonly Lock writing = new();
    /// The bytes of every part the file holds, as last committed.
    private readonly Dictionary<string, byte[]> written;
    private SessionState? writtenSession;
    private NativeSyncJournal? writtenJournal;
    /// The newest accepted session revision not yet written.
    private Unwritten<(SessionState Session, ulong Revision)>? pending;
    /// The newest device records not yet written, and those the file holds,
    /// or null while the file's device store could not be read.
    private Unwritten<DeviceRecords>? pendingDevice;
    private DeviceRecords? writtenDevice;
    /// The newest session revision handed to the file or saved durably, and
    /// the newest one the file holds.
    private ulong handedRevision, writtenRevision;
    /// The newest file revision handed out, and the newest one `Saved` named.
    private ulong fileRevision, savedRevision;
    private bool pendingIsNew, stopping, closed;

    public string Directory { get; }

    /// What the device store held when the file was opened.
    public DeviceRecords Device { get; }

    /// The cloud transport's state the device store held when the file was
    /// opened, or null while it held none.
    public CloudTransportRecord? CloudTransport { get; }

    /// Whether a restore or a replaced session left the cloud-recovery marker
    /// beside the file for the transport to start over from a full pull.
    public bool CloudRecoveryRequested => File.Exists(Path.Combine(Directory, FileName) + CloudRecoverySuffix);

    /// The newest file revision handed to the file and not yet on disk, or null.
    public ulong? PendingRevision {
        get {
            lock (queue) return WrittenThrough < fileRevision ? fileRevision : null;
        }
    }

    /// Whether the file holds a session.
    public bool HoldsSession {
        get {
            lock (writing) return written.ContainsKey(StoragePart.Core.Name);
        }
    }

    /// The newest file revision up to which everything is on disk. The caller
    /// holds the queue lock.
    private ulong WrittenThrough => Math.Min(pending?.Since ?? fileRevision + 1, pendingDevice?.Since ?? fileRevision + 1) - 1;

    #endregion

    #region Constructors

    private SessionStorage(string directory, SqliteConnection connection, Dictionary<string, byte[]> parts,
        NativeSyncJournal? journal, DeviceRecords? device, CloudTransportRecord? cloudTransport, Action<Change> announce) {
        Directory = directory;
        this.connection = connection;
        written = parts;
        Device = device ?? DeviceRecords.Empty;
        CloudTransport = cloudTransport;
        writtenDevice = device;
        writtenJournal = journal;
        this.announce = announce;
        worker = new Thread(Run) { IsBackground = true, Name = "Crest session storage" };
        worker.Start();
    }

    /// Opens `session.sqlite` in `directory`, creating both when absent, and
    /// answers what it held in `loaded`. An existing file is validated
    /// read-only first, because a writable connection may replay or truncate a
    /// damaged WAL that recovery still needs. Throws `Rejected` naming why the
    /// file cannot be used.
    public static SessionStorage Open(string directory, Action<Change> announce, out StoredSession loaded) {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        ArgumentNullException.ThrowIfNull(announce);
        string path = Path.Combine(directory, FileName);
        if (File.Exists(path + RestoreMarkerSuffix)) throw new Rejected(new StorageRestoreInterrupted());
        try {
            CreateDirectory(directory);
            var validated = File.Exists(path) ? Validate(path) : null;
            var connection = SqliteConnection.Open(path, Sqlite.OpenReadWrite | Sqlite.OpenCreate);
            try {
                RequireVersion(connection.ReadUserVersion());
                connection.Execute("PRAGMA journal_mode=WAL");
                connection.Execute("PRAGMA synchronous=FULL");
                connection.InTransaction(() => {
                    connection.Execute("CREATE TABLE IF NOT EXISTS checkpoint (part TEXT PRIMARY KEY, data BLOB NOT NULL)");
                    connection.CreateDeviceTables();
                    connection.Execute($"PRAGMA user_version={StorageVersion}");
                });
                var parts = ReadAll(connection);
                loaded = validated is { } earlier && SameParts(earlier.Parts, parts) ? earlier.Session : StoredSession.Decode(parts);
                return new(directory, connection, parts, loaded.Journal, ReadDevice(connection), ReadCloudTransport(connection),
                    announce);
            } catch {
                connection.Dispose();
                throw;
            }
        } catch (StorageException error) {
            throw new Rejected(new StorageUnreadable(error.Reason));
        } catch (IOException) {
            throw new Rejected(new StorageUnreadable(StorageFailure.Unavailable));
        } catch (UnauthorizedAccessException) {
            throw new Rejected(new StorageUnreadable(StorageFailure.ReadOnly));
        }
    }

    #endregion

    #region Actions - Opening

    private static void CreateDirectory(string directory) {
        if (OperatingSystem.IsWindows()) System.IO.Directory.CreateDirectory(directory);
        else System.IO.Directory.CreateDirectory(directory, OwnerOnly);
    }

    private static string[] WithSidecars(string path) => [path, .. SidecarSuffixes.Select(suffix => path + suffix)];

    /// Reads and decodes an existing file through a read-only connection. A
    /// cleanly closed WAL database has no sidecar, and a read-only connection
    /// cannot recreate one, so a file without a WAL is read as immutable.
    private static (Dictionary<string, byte[]> Parts, StoredSession Session)? Validate(string path) {
        bool standalone = !File.Exists(path + SidecarSuffixes[0]);
        string source = standalone ? new Uri(path).AbsoluteUri + "?immutable=1" : path;
        using var validation = SqliteConnection.Open(source, Sqlite.OpenReadOnly | Sqlite.OpenUri);
        int version = validation.ReadUserVersion();
        RequireVersion(version);
        if (version != StorageVersion) return null;
        var parts = ReadAll(validation);
        return (parts, StoredSession.Decode(parts));
    }

    private static void RequireVersion(int version) {
        if (version > StorageVersion) throw new Rejected(new StorageFromNewerApp());
        if (version < 0) throw new Rejected(new StorageUnreadable(StorageFailure.Damaged));
    }

    /// The device store, or null when it cannot be read: the session never
    /// depends on it, and the next write rewrites every part of it.
    private static DeviceRecords? ReadDevice(SqliteConnection source) {
        try {
            return source.ReadDevice();
        } catch (StorageException) {
            return null;
        }
    }

    /// The cloud transport's state, or null when the store keeps none or it
    /// cannot be read: the transport then starts over from a full pull.
    private static CloudTransportRecord? ReadCloudTransport(SqliteConnection source) {
        try {
            return source.ReadCloudTransport();
        } catch (StorageException) {
            return null;
        }
    }

    private static Dictionary<string, byte[]> ReadAll(SqliteConnection source) =>
        source.Parts().ToDictionary(part => part, part => source.Read(part)!, StringComparer.Ordinal);

    private static bool SameParts(Dictionary<string, byte[]> first, Dictionary<string, byte[]> second) =>
        first.Count == second.Count
        && first.All(part => second.TryGetValue(part.Key, out var bytes) && bytes.AsSpan().SequenceEqual(part.Value));

    #endregion

    #region Actions - Saving

    /// Hands the worker a published revision to save behind, at the next file
    /// revision. A revision no newer than one already handed or saved durably
    /// is ignored.
    public void Enqueue(SessionState session, ulong revision) {
        ArgumentNullException.ThrowIfNull(session);
        lock (queue) {
            if (stopping || revision <= handedRevision) return;
            handedRevision = revision;
            pending = Unwritten<(SessionState, ulong)>.Replacing(pending, (session, revision), ++fileRevision);
            pendingIsNew = true;
            Monitor.Pulse(queue);
        }
    }

    /// Writes `session` at `revision`, with `journal` when it changed, before
    /// returning; `encoded` holds parts already encoded for it. Throws
    /// `StorageException` and leaves the file as it was when the write fails.
    public void Save(SessionState session, ulong revision, NativeSyncJournal? journal = null,
        NativeSessionCheckpoint? encoded = null) {
        ArgumentNullException.ThrowIfNull(session);
        Announce(Write(session, revision, journal, encoded));
    }

    /// Writes `journal` before returning, in one transaction with the newest
    /// accepted session that is not on disk yet.
    public void SaveJournal(NativeSyncJournal journal) {
        ArgumentNullException.ThrowIfNull(journal);
        Announce(Write(null, 0, journal));
    }

    /// Writes the first session into a file that holds none, with the journal
    /// that goes with it. Throws `StorageException` when the write fails.
    public void Install(SessionState session, NativeSyncJournal? journal) {
        ArgumentNullException.ThrowIfNull(session);
        lock (writing) {
            RequireOpen();
            if (written.ContainsKey(StoragePart.Core.Name)) throw new InvalidOperationException("The file already holds a session.");
            WriteParts(session, journal);
        }
    }

    /// Hands the worker the device records to save behind, at the next file
    /// revision. The newest records replace any that are still pending.
    public void EnqueueDevice(DeviceRecords records) {
        ArgumentNullException.ThrowIfNull(records);
        lock (queue) {
            if (stopping) return;
            pendingDevice = Unwritten<DeviceRecords>.Replacing(pendingDevice, records, ++fileRevision);
            pendingIsNew = true;
            Monitor.Pulse(queue);
        }
    }

    /// Writes the cloud transport's state, when `record` holds one, and the
    /// change of its server fields, with `adoption`'s marker when it is one,
    /// in one transaction before returning. Throws `StorageException` and
    /// leaves the file as it was when the write fails.
    public void SaveCloudTransport(CloudTransportRecord? record, CloudFieldWrite? fields, DeviceAdoption? adoption) {
        lock (writing) {
            RequireOpen();
            connection.InTransaction(() => {
                if (record is not null) connection.WriteCloudTransport(record);
                if (fields is not null) connection.WriteCloudFields(fields.Clearing, fields.Updated, fields.Removed);
                if (adoption is not null) connection.MarkAdopted(adoption);
            });
        }
    }

    /// The server fields the device store keeps of `names`. Throws
    /// `StorageException` when they cannot be read.
    public IReadOnlyList<CloudRecordFields> CloudFields(IReadOnlyList<string> names) {
        ArgumentNullException.ThrowIfNull(names);
        lock (writing) {
            RequireOpen();
            return connection.ReadCloudFields(names);
        }
    }

    /// Writes the device records before returning, in place of every record
    /// handed to the worker before them: the caller reads and saves them under
    /// the device lock, so they are the newest. Throws `StorageException` and
    /// leaves the file as it was when the write fails.
    public void SaveDevice(DeviceRecords records) {
        ArgumentNullException.ThrowIfNull(records);
        Saved? saved;
        lock (writing) {
            RequireOpen();
            connection.InTransaction(() => connection.WriteDevice(records, writtenDevice));
            writtenDevice = records;
            lock (queue) {
                pendingDevice = null;
                saved = Advance();
            }
        }
        Announce(saved);
    }

    private void Run() {
        while (true) {
            lock (queue) {
                while (!pendingIsNew && !stopping) Monitor.Wait(queue);
                if (!pendingIsNew) return;
                pendingIsNew = false;
            }
            Announce(WriteBehind());
            Announce(WriteDeviceBehind());
        }
    }

    /// Saves the newest pending device records, answering `Saved` when the
    /// file now holds a newer file revision. What is owed is read under the
    /// writer lock, so records a durable save superseded are never written over
    /// it. A failure is published, and the records stay pending for the next
    /// attempt.
    private Change? WriteDeviceBehind() {
        try {
            lock (writing) {
                Unwritten<DeviceRecords>? owed;
                lock (queue) owed = pendingDevice;
                if (owed is null) return null;
                var records = owed.Value;
                RequireOpen();
                if (!records.Equals(writtenDevice)) connection.InTransaction(() => connection.WriteDevice(records, writtenDevice));
                writtenDevice = records;
                lock (queue) {
                    pendingDevice = pendingDevice?.After(owed.Revision);
                    return Advance();
                }
            }
        } catch (Exception error) {
            return new StorageFailed(error is StorageException storage ? storage.Reason : StorageFailure.Unavailable);
        }
    }

    /// Saves the newest pending revision. A failure is published, and the
    /// revision stays pending for the next attempt.
    private Change? WriteBehind() {
        try {
            return Write(null, 0, null);
        } catch (Exception error) {
            return new StorageFailed(error is StorageException storage ? storage.Reason : StorageFailure.Unavailable);
        }
    }

    /// Writes one transaction under the writer lock: `session` or, without
    /// one, the newest pending revision, and `journal`. A durable `session`
    /// takes the next file revision once it is written. Answers `Saved` when
    /// the file now holds a newer file revision.
    private Saved? Write(SessionState? session, ulong revision, NativeSyncJournal? journal,
        NativeSessionCheckpoint? encoded = null) {
        lock (writing) {
            RequireOpen();
            Unwritten<(SessionState Session, ulong Revision)>? owed = null;
            if (session is null) {
                lock (queue) {
                    if (pending is { } next && next.Value.Revision > writtenRevision) {
                        owed = next;
                        (session, revision) = next.Value;
                    }
                }
            } else if (revision <= writtenRevision) {
                throw new InvalidOperationException("A durable save must be newer than the file.");
            }
            if (session is null && journal is null) return null;
            WriteParts(session, journal, encoded);
            if (session is null) return null;
            writtenRevision = revision;
            lock (queue) {
                if (owed is not null) {
                    pending = pending?.After(owed.Revision);
                } else {
                    handedRevision = Math.Max(handedRevision, revision);
                    fileRevision++;
                    if (pending is { } superseded && superseded.Value.Revision <= revision) pending = null;
                }
                return Advance();
            }
        }
    }

    /// `Saved` for the newest file revision up to which everything is on
    /// disk, when `Saved` has not named it yet. The caller holds the queue lock.
    private Saved? Advance() {
        var through = WrittenThrough;
        if (through <= savedRevision) return null;
        savedRevision = through;
        return new Saved(checked((long)through));
    }

    /// Writes every part of `session` and `journal` whose bytes changed, in
    /// one transaction. The caller holds the writer lock.
    private void WriteParts(SessionState? session, NativeSyncJournal? journal, NativeSessionCheckpoint? encoded = null) {
        var puts = new List<(string Part, byte[] Data)>();
        var removals = new List<string>();
        if (session is not null) {
            var checkpoint = encoded ?? new NativeSessionCheckpoint(session);
            AddIfChanged(puts, StoragePart.Core, checkpoint.Core());
            var previous = writtenSession?.Spaces.ToDictionary(space => space.Id) ?? [];
            var retained = new HashSet<string>(StringComparer.Ordinal);
            foreach (var space in session.Spaces) {
                var part = StoragePart.History(space.Id);
                retained.Add(part.Name);
                // History that is the same list the file already holds needs no encoding.
                if (written.ContainsKey(part.Name) && previous.TryGetValue(space.Id, out var earlier)
                    && ReferenceEquals(earlier.History, space.History)) continue;
                AddIfChanged(puts, part, checkpoint.History(space.Id));
            }
            removals.AddRange(written.Keys.Where(name => new StoragePart(name).IsHistory && !retained.Contains(name)));
        }
        if (journal is not null && !ReferenceEquals(journal, writtenJournal)) AddIfChanged(puts, StoragePart.Journal, journal.Read());
        if (puts.Count > 0 || removals.Count > 0) {
            connection.InTransaction(() => {
                foreach (var (part, data) in puts) connection.Write(part, data);
                foreach (var part in removals) connection.Remove(part);
            });
            foreach (var (part, data) in puts) written[part] = data;
            foreach (var part in removals) written.Remove(part);
        }
        if (session is not null) writtenSession = session;
        if (journal is not null) writtenJournal = journal;
    }

    private void AddIfChanged(List<(string Part, byte[] Data)> puts, StoragePart part, byte[] data) {
        if (!written.TryGetValue(part.Name, out var current) || !current.AsSpan().SequenceEqual(data)) puts.Add((part.Name, data));
    }

    private void RequireOpen() {
        if (closed) throw new StorageException(StorageFailure.Unavailable, "The session file is closed.");
    }

    private void Announce(Change? change) {
        if (change is not null) announce(change);
    }

    #endregion

    #region Actions - Recovery

    /// Preserves the file as it is now, WAL included, as the standalone
    /// recovery checkpoint, when it holds both a session and a journal.
    /// Recovery restores it after a launch that cannot read the file.
    public void SaveRecoveryCheckpoint() {
        lock (writing) {
            RequireOpen();
            if (!written.ContainsKey(StoragePart.Core.Name) || !written.ContainsKey(StoragePart.Journal.Name)) return;
            string temporary = Path.Combine(Directory, Guid.NewGuid().ToString("D").ToUpperInvariant() + TemporaryExtension);
            try {
                connection.Backup(temporary);
                File.Move(temporary, Path.Combine(Directory, RecoveryFileName), overwrite: true);
            } finally {
                foreach (var file in SidecarSuffixes.Select(suffix => temporary + suffix).Prepend(temporary)) File.Delete(file);
            }
        }
    }

    /// Leaves the cloud-recovery marker beside the file, before the seed that
    /// stands in for an unreadable installed session is written.
    public void RequestCloudRecovery() => RequestCloudRecovery(Path.Combine(Directory, FileName));

    /// Removes the cloud-recovery marker once the transport's state starts
    /// over. A marker that cannot be removed is honoured again next launch,
    /// which pulls everything again and changes nothing else.
    public void ConsumeCloudRecovery() {
        try {
            File.Delete(Path.Combine(Directory, FileName) + CloudRecoverySuffix);
        } catch (IOException) {
        } catch (UnauthorizedAccessException) {
        }
    }

    private static void RequestCloudRecovery(string path) => File.WriteAllBytes(path + CloudRecoverySuffix, []);

    /// Replaces the file in `directory` with its recovery checkpoint while no
    /// core has it open. The checkpoint is validated read-only first, and the
    /// file is touched only once a copy of it with every part decoded is ready:
    /// that copy's journal gets a new device identity, so it never reissues a
    /// version it issued after the checkpoint. The file and its sidecars are
    /// preserved in a `Recovery-` directory beside it, and the restore marker
    /// names that directory until the copy is in place, so an interrupted
    /// restore refuses the directory instead of starting a fresh session. The
    /// cloud-recovery marker stays for the transport. Throws `Rejected`.
    public static void Restore(string directory) {
        ArgumentException.ThrowIfNullOrWhiteSpace(directory);
        string path = Path.Combine(directory, FileName);
        string checkpoint = Path.Combine(directory, RecoveryFileName);
        string candidate = Path.Combine(directory, Guid.NewGuid().ToString("D").ToUpperInvariant() + TemporaryExtension);
        try {
            if (!File.Exists(checkpoint)) throw new Rejected(new RecoveryCheckpointUnusable(StorageFailure.Unavailable));
            var journal = RestorableJournal(checkpoint);
            File.Copy(checkpoint, candidate);
            using (var copy = SqliteConnection.Open(candidate, Sqlite.OpenReadWrite))
                copy.Write(StoragePart.Journal.Name, journal.Recovered(Guid.NewGuid()).Read());
            string preserved = Path.Combine(directory, PreservedDirectoryPrefix + Guid.NewGuid().ToString("D").ToUpperInvariant());
            CreateDirectory(preserved);
            foreach (var file in WithSidecars(path).Where(File.Exists))
                File.Copy(file, Path.Combine(preserved, Path.GetFileName(file)));
            File.WriteAllText(path + RestoreMarkerSuffix, preserved);
            RequestCloudRecovery(path);
            foreach (var sidecar in WithSidecars(path).Skip(1)) File.Delete(sidecar);
            File.Move(candidate, path, overwrite: true);
            File.Delete(path + RestoreMarkerSuffix);
        } catch (StorageException error) {
            throw new Rejected(new RecoveryCheckpointUnusable(error.Reason));
        } catch (IOException) {
            throw new Rejected(new RecoveryCheckpointUnusable(StorageFailure.Unavailable));
        } catch (UnauthorizedAccessException) {
            throw new Rejected(new RecoveryCheckpointUnusable(StorageFailure.ReadOnly));
        } finally {
            foreach (var file in WithSidecars(candidate).Append(candidate + RollbackJournalSuffix)) File.Delete(file);
        }
    }

    /// The journal of a checkpoint this build wrote whose every part decodes.
    private static NativeSyncJournal RestorableJournal(string checkpoint) {
        try {
            var validated = Validate(checkpoint);
            if (validated is { Session: { Session: not null, Journal: { } journal } }) return journal;
        } catch (Rejected) {
            // A checkpoint no build could have written is as unusable as a damaged one.
        }
        throw new Rejected(new RecoveryCheckpointUnusable(StorageFailure.Damaged));
    }

    #endregion

    #region Actions - Lifetime

    /// Saves any revision still pending, then closes the file.
    public void Dispose() {
        lock (queue) {
            if (stopping) return;
            stopping = true;
            Monitor.Pulse(queue);
        }
        worker.Join();
        Announce(WriteBehind() is Saved saved ? saved : null);
        Announce(WriteDeviceBehind());
        lock (writing) {
            closed = true;
            connection.Dispose();
        }
    }

    #endregion
}
