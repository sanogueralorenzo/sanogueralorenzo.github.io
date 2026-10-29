using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// The core's typed application API. An intent changes state and answers the
/// changes it published, or throws `Rejected`; a query answers without
/// changing anything. Each area handles its own intents and queries. One lock
/// serializes every call on this instance, except the cloud transport's: its
/// intents compute on the transport's thread and take the lock only to
/// commit, and its queries read the journal without it.
///
/// Changes the core starts itself, such as a finished save, a session commit,
/// a cloud merge or an engine's report, wait in a pending batch the host
/// drains after its wake callback runs. An intent the host sends answers that
/// batch first, so no older change arrives after a newer one. Commands for
/// engine bindings wait in a queue that is delivered once the lock is
/// released, on the thread of the host's call that caused them, or of its next
/// drain for those the transport caused.
public sealed partial class CrestApp : IQueryAnswers, IDisposable {
    #region Variables

    private readonly Lock gate = new();
    internal Lock Gate => gate;
    /// This device's windows and what each shows.
    private readonly Device device;
    /// The cloud transport's state on this device.
    private readonly CloudTransportStore cloudTransport;
    /// What iCloud sync does next on this device.
    private readonly CloudSyncControl cloudSync;
    /// The time session intents are stamped with.
    private readonly IClock clock;
    /// Where the identities the core gives new records come from.
    private readonly IIdSource ids;
    /// Reading other browsers' data and browser-data files, and exports.
    private readonly Portability portability;

    // The areas each message routes itself to, which only the core's own
    // messages reach.
    internal Device Device => device;
    internal CloudTransportStore CloudTransport => cloudTransport;
    internal CloudSyncControl CloudSync => cloudSync;
    internal IClock Clock => clock;
    internal IIdSource Ids => ids;
    internal Portability Portability => portability;

    #endregion

    #region Constructors

    /// A core that keeps everything in memory.
    public CrestApp() : this(new AppConfiguration(null, DevicePlatform.Desktop)) { }

    /// A core configured by the host. With a storage directory it opens the
    /// session file there and loads the session it holds; throws `Rejected`
    /// when the file cannot be used.
    public CrestApp(AppConfiguration configuration) : this(configuration, new SystemClock(), new SystemIdSource()) { }

    /// A core that reads the time from `clock` and draws new identities from `ids`.
    internal CrestApp(AppConfiguration configuration, IClock clock, IIdSource ids) {
        ArgumentNullException.ThrowIfNull(configuration);
        ArgumentNullException.ThrowIfNull(clock);
        ArgumentNullException.ThrowIfNull(ids);
        this.clock = clock;
        this.ids = ids;
        portability = new(configuration.ImportNames, clock, ids);
        if (configuration.StorageDirectory is not { } directory) {
            device = new(configuration.Platform, storage: null, DeviceRecords.Empty, Announce, RequestTurn, CloseBorrower, clock);

            cloudTransport = new(storage: null, device);
            cloudSync = new(cloudTransport, clock, StoredSessionIsDisposableSeed, StoredJournalPendingUploads);
            return;
        }
        storage = SessionStorage.Open(directory, Announce, out var loaded);
        device = new(configuration.Platform, storage, storage.Device, Announce, RequestTurn, CloseBorrower, clock);

        cloudTransport = new(storage, device);
        cloudSync = new(cloudTransport, clock, StoredSessionIsDisposableSeed, StoredJournalPendingUploads);
        try {
            if (loaded.Session is { } stored) Establish(stored, loaded.Journal, loaded.LegacySelection);
        } catch (Exception error) {
            storage.Dispose();
            if (error is Rejected) throw;
            throw new Rejected(new StorageUnreadable(StorageFailure.Damaged));
        }
    }

    #endregion

    #region Actions - Intents

    /// The changes still pending when the intent ran and those it published
    /// there, in the order they happened, then the changes the intent itself
    /// published. An intent that does not apply to the current state publishes
    /// none. An intent of the cloud
    /// transport answers only its receipts; see `CloudSyncIntent`.
    public IReadOnlyList<Change> Send(Intent intent) {
        ArgumentNullException.ThrowIfNull(intent);
        return intent.Route(this);
    }

    /// Commits one session/device turn under the core lock, then returns its
    /// changes after any earlier pending changes.
    internal IReadOnlyList<Change> Turn(Action<ChangeFeed> apply) {
        IReadOnlyList<Change> published;
        storedSync?.RequireNoTransactionHeldHere();
        lock (gate) {
            var changes = new ChangeFeed();
            apply(changes);
            published = [.. TakePending(), .. changes.Published];
        }
        WakeForRequestedTurn();
        return published;
    }

    /// What a device intent reads in a turn that publishes to `changes`: the
    /// core's time and identity source.
    internal DeviceTurn DeviceTurn(ChangeFeed changes) => new(changes, clock.Now, ids);

    #endregion

    #region Actions - Queries

    /// The answer, or `Rejected` naming the rule that refuses the question.
    /// A question that reads what the app holds is answered under its lock.
    public TAnswer Query<TAnswer>(Query<TAnswer> query) {
        ArgumentNullException.ThrowIfNull(query);
        if (!query.AnsweredUnderLock) return query.Answer(this);
        lock (gate) return query.Answer(this);
    }

    #endregion

    #region Actions - Lifetime

    /// Stages and saves any accepted revision still pending and closes the
    /// session file. The stored session accepts no edits afterwards.
    public void Dispose() {
        storedSync?.Stop();
        storedSession?.Close();
        storage?.Dispose();
    }

    #endregion
}
