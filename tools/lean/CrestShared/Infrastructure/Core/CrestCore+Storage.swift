import CrestCoreABI
import Foundation
import OSLog

extension CrestCore {
    // MARK: - Actions - Saves

    /// Returns once every edit the core accepted before the call is on disk,
    /// what its saved windows show included, or once a save the core started
    /// itself has failed. Drains keep running while it waits, so the main
    /// actor stays free.
    func flushPendingSaves() async {
        guard let revision = try? query(PendingSave()).revision else { return }
        await saved(through: revision)
    }

    /// Returns once file revision `revision` or a newer one is on disk, or
    /// once a save the core started itself has failed.
    func saved(through revision: Int64) async {
        guard state.savedRevision < revision else { return }
        await withCheckedContinuation { continuation in
            saveWaiters.append((revision, continuation))
        }
    }

    func resumeSaveWaiters() {
        let saved = state.savedRevision
        let ready = saveWaiters.filter { $0.revision <= saved }
        saveWaiters.removeAll { $0.revision <= saved }
        for waiter in ready { waiter.continuation.resume() }
    }

    /// A failed save surfaces through the handler and releases every waiter:
    /// the revisions they wait for stay pending until a later save succeeds.
    func storageFailed(_ reason: StorageFailure) {
        Logger(subsystem: "com.pauldavis.crest", category: "SessionStorage")
            .error("The core could not save the session: \(String(describing: reason), privacy: .public)")
        storageFailureHandler?(reason)
        let waiting = saveWaiters
        saveWaiters.removeAll()
        for waiter in waiting { waiter.continuation.resume() }
    }

    // MARK: - Actions - Stored session

    /// Replaces the session file in `configuration`'s directory with the
    /// recovery checkpoint the last good launch kept. No core may have that
    /// directory open. Throws the rejection naming why it cannot.
    nonisolated static func restoreRecoveryCheckpoint(configuration: AppConfiguration) throws(Rejection) {
        var writer = WireWriter()
        configuration.encode(into: &writer)
        var refusal = crest_buffer_t()
        let status = CoreCodec.fingerprint.withUnsafeBufferPointer { fingerprint in
            writer.bytes.withUnsafeBufferPointer { settings in
                crest_app_restore(
                    fingerprint.baseAddress, fingerprint.count, settings.baseAddress, settings.count, &refusal)
            }
        }
        defer { crest_buffer_free(&refusal) }
        switch status {
        case CREST_OK:
            return
        case CREST_REJECTED:
            throw rejection(in: refusal)
        default:
            buildBug(status, "restore its recovery checkpoint")
        }
    }
}
