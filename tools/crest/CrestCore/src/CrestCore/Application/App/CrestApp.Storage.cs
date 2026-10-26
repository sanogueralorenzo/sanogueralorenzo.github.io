using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

public sealed partial class CrestApp {
    #region Variables

    private readonly SessionStorage? storage;
    internal SessionStorage? Storage => storage;

    /// The session this core keeps in its file, as it loaded and repaired it,
    /// once the file holds one. `OpenWorkspace` opens it. Set once, under the
    /// lock; the cloud transport's calls read it without the lock.
    private volatile NativeSessionAuthority? storedSession;
    internal NativeSessionAuthority? StoredSession => storedSession;
    /// The sync component the file's session stages into, kept beside it. Set
    /// with `storedSession`.
    private volatile NativeSyncAuthority? storedSync;
    /// The selection an older release kept in the stored session, which the
    /// windows of the launch that loaded it adopt.
    private JsonObject? storedSelection;
    /// The tabs the repair gave a new identity, each with the tab whose image
    /// it wears.
    private IReadOnlyList<(Guid Source, Guid Copy)> repairedCopies = [];

    /// The sync component of the session this core keeps in its file, which
    /// the tests read the journal of; null while the file holds no session.
    internal NativeSyncAuthority? StoredSync => storedSync;

    #endregion

    #region Actions - Stored session

    /// Replaces the session file in `configuration`'s directory with the
    /// recovery checkpoint the last good launch kept, while no core has that
    /// file open. Throws `Rejected` naming why it cannot; see
    /// `SessionStorage.Restore`.
    public static void RestoreRecoveryCheckpoint(AppConfiguration configuration) {
        ArgumentNullException.ThrowIfNull(configuration);
        if (configuration.StorageDirectory is not { } directory)
            throw new Rejected(new RecoveryCheckpointUnusable(StorageFailure.Unavailable));
        SessionStorage.Restore(directory);
    }

    /// Makes a stored session the one `OpenWorkspace` opens from the file. The
    /// recovery checkpoint preserves the file exactly as loaded before anything
    /// else is written; the repaired session is then the first save.
    internal void Establish(SessionState stored, NativeSyncJournal? journal, JsonObject? legacySelection) {
        var target = storage!;
        try {
            target.SaveRecoveryCheckpoint();
        } catch (Exception error) when (error is StorageException or IOException or UnauthorizedAccessException) {
            // A launch that cannot preserve a copy still opens the session it read.
        }
        SessionState repaired;
        IReadOnlyList<NativeSessionMaintenance.TabOrigin> origins;
        try {
            repaired = NativeSessionMaintenance.Repair(stored, DateTimeOffset.UtcNow, null, new SystemIdSource(), out origins);
        } catch (BrowserRuleException) {
            throw new Rejected(new StorageUnreadable(StorageFailure.Damaged));
        }
        storedSession = new NativeSessionAuthority(repaired, target);
        storedSync = new NativeSyncAuthority(journal ?? NativeSyncJournal.Fresh(Guid.NewGuid()));
        storedSelection = legacySelection;
        repairedCopies = NativeSessionMaintenance.Copies(repaired, origins);
    }

    #endregion
}
