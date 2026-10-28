using CrestCore.Contracts;

namespace CrestCore.Application;

/// The cloud transport's state on this device, which the device store keeps
/// beside the session and never syncs: the engine's saved cursor, the server
/// fields of every uploaded record, and the rules for when a download must be
/// recovered with a full pull, when an account change waits for the person,
/// and when this device's copy overwrites the cloud's. The transport runs its
/// intents on its own thread; this takes its own lock, never the host's.
internal sealed class CloudTransportStore {
    #region Variables

    private readonly Lock gate = new();
    internal Lock Gate => gate;
    internal SessionStorage? Storage { get; }
    internal Device Device { get; }
    /// Each record's server fields, when no file keeps them.
    private readonly Dictionary<string, CloudRecordFields> memoryFields = new(StringComparer.Ordinal);
    internal Dictionary<string, CloudRecordFields> MemoryFields => memoryFields;
    /// The failures counted when each merge under way began.
    internal Dictionary<long, int> Merges { get; } = [];

    internal CloudTransportRecord Record { get; set; }
    internal bool Adopted { get; set; }
    /// Sync was turned off before the installed release's state was adopted:
    /// the adoption starts it over unless an account decision waits.
    internal bool ResetsOnAdoption { get; set; }
    /// A merge failed, or an earlier launch left one unrecovered, and no full
    /// snapshot has been taken since without another failing meanwhile.
    internal bool NeedsRecovery { get; set; }
    internal int FailedMerges { get; set; }
    private long lastMerge;

    #endregion

    #region Constructors

    /// The state `storage` kept, or a transport that starts over in memory.
    /// A restore or a replaced session left the recovery marker: once the
    /// state was adopted, it starts over from a full pull now.
    public CloudTransportStore(SessionStorage? storage, Device device) {
        ArgumentNullException.ThrowIfNull(device);
        this.Storage = storage;
        this.Device = device;
        Adopted = device.HasAdopted(DeviceAdoption.CloudTransport);
        Record = storage?.CloudTransport ?? CloudTransportRecord.Initial(recordSchema: 0);
        NeedsRecovery = Record.RequiresFullPull;
        if (!Adopted || storage is not { CloudRecoveryRequested: true }) return;
        try {
            Recover();
        } catch (Rejected) {
            // The marker stays, so the next launch recovers instead.
        }
    }

    #endregion

    #region Actions - Intents

    /// Runs one transport intent, saving what it changed before it returns,
    /// and answers the state it left. `journalHoldsUploads` tells whether the
    /// stored session's journal still holds records waiting to upload, once
    /// every stage queued before settled. Throws `Rejected`.
    public IReadOnlyList<Change> Handle(CloudTransportIntent intent, Func<bool> journalHoldsUploads) =>
        intent.Apply(this, journalHoldsUploads);

    /// Applies `change` holding the store's lock, and answers the state it left.
    internal IReadOnlyList<Change> Changing(Action change) {
        lock (gate) {
            change();
            return [Changed()];
        }
    }

    /// Runs `read` holding the store's lock.
    internal IReadOnlyList<Change> Locked(Func<IReadOnlyList<Change>> read) {
        lock (gate) return read();
    }

    /// Whether an account change waits for the person's decision.
    public bool AwaitsAccountDecision {
        get {
            lock (gate) return Record.AwaitsAccountDecision;
        }
    }

    /// Starts the transport's state over, as `ResetCloudTransport` does.
    /// Throws `Rejected` with `SaveFailed`, keeping what was there.
    public void Reset(bool overwritesCloud) {
        lock (gate) StartOver(overwritesCloud);
    }

    /// Starts the transport's state over unless an account decision waits,
    /// as turning sync off does; before the installed release's state is
    /// adopted, the adoption does. Throws `Rejected` with `SaveFailed`.
    public void ResetUnlessAwaitingDecision() {
        lock (gate) {
            if (!Adopted) ResetsOnAdoption = true;
            else if (!Record.AwaitsAccountDecision) StartOver(overwritesCloud: false);
        }
    }

    /// No cursor, no server fields, no full pull and no account decision
    /// waiting, in one save. The caller holds the lock.
    internal void StartOver(bool overwritesCloud) {
        NeedsRecovery = false;
        Save(CloudTransportRecord.Initial(Record.RecordSchema) with { OverwritesCloud = overwritesCloud }, CloudFieldWrite.Cleared);
    }

    /// Starts over from a full pull, keeping an account decision that waits,
    /// and removes the marker that asked for it. The caller holds the lock or
    /// is the constructor.
    private void Recover() {
        Save(Record.Recovering(), CloudFieldWrite.Cleared);
        NeedsRecovery = true;
        Storage!.ConsumeCloudRecovery();
    }

    /// Notes that a full pull must recover the merge that begins, before it
    /// begins, and answers its name. A note that cannot be saved counts as a
    /// failed merge. The caller holds the lock.
    internal IReadOnlyList<Change> Begin() {
        try {
            Save(Record with { RequiresFullPull = true }, fields: null);
        } catch (Rejected) {
            FailedMerges++;
            NeedsRecovery = true;
            throw;
        }
        long id = ++lastMerge;
        Merges[id] = FailedMerges;
        return [new CloudMergeBegan(id), Changed()];
    }

    /// Saves `next` and `fields` before keeping them; with `adoption`, its
    /// marker in the same transaction. Throws `Rejected` with `SaveFailed`,
    /// keeping what was there. The caller holds the lock.
    internal void Save(CloudTransportRecord? next, CloudFieldWrite? fields, DeviceAdoption? adoption = null) {
        if (Storage is { } target) {
            try {
                target.SaveCloudTransport(next, fields, adoption);
            } catch (StorageException error) {
                throw new Rejected(new SaveFailed(error.Reason));
            }
        } else if (fields is not null) {
            if (fields.Clearing) memoryFields.Clear();
            foreach (var name in fields.Removed) memoryFields.Remove(name);
            foreach (var kept in fields.Updated) memoryFields[kept.RecordName] = kept;
        }
        if (next is not null) Record = next;
    }

    private CloudTransportChanged Changed() => new(Record.Published(Adopted));

    #endregion
}
