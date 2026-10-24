#ifndef CREST_APP_H
#define CREST_APP_H

/* The typed application API. Intents, changes, rejections, queries and their
 * answers cross as the generated positional wire format; crest_contracts.h
 * names the tags and the schema fingerprint. Swift and the core always ship
 * in one build, so the wire has no versioning: creation checks the
 * fingerprint instead. Calls are synchronous and serialized per app.
 *
 * Every buffer the core returns was allocated by the core; release it with
 * crest_buffer_free. Statuses other than OK and REJECTED are caller or build
 * bugs: INVALID_MESSAGE (bytes that do not decode, or trailing bytes),
 * LIMIT_EXCEEDED (a message longer than its type's limit: 16 MiB, or one
 * stored session part, 64 MiB, for the intent that carries an installed
 * session), INVALID_HANDLE, VERSION_MISMATCH and INTERNAL_ERROR.
 */
#include "crest_core.h"

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint8_t* bytes;
    size_t length;
} crest_buffer_t;

/* A rule refused the intent or query; the buffer holds one rejection. */
#define CREST_REJECTED ((crest_status_t)6)

/* configuration is one encoded AppConfiguration. With a storage directory the
 * core opens session.sqlite there (creating both when absent), loads the
 * session it holds and saves every accepted revision to it; without one it
 * keeps everything in memory. VERSION_MISMATCH when the fingerprint is not
 * this core's schema. REJECTED: out_rejection holds one rejection naming why
 * the file cannot be used (StorageUnreadable, StorageFromNewerApp,
 * StorageRestoreInterrupted); nothing was written to it. */
CREST_API crest_status_t CREST_CALL crest_app_create(const uint8_t* fingerprint, size_t length,
    const uint8_t* configuration, size_t configuration_length, uint64_t* out_app, crest_buffer_t* out_rejection);
/* Replaces session.sqlite in the configured storage directory with the
 * recovery checkpoint the last good launch kept, while no app has that
 * directory open. The checkpoint is validated read-only and its journal gets a
 * new device identity before the file is touched; the file and its sidecars
 * are preserved in a Recovery- directory beside it, and the cloud-recovery
 * marker is left for the cloud transport. REJECTED: out_rejection holds one
 * rejection (RecoveryCheckpointUnusable); a restore interrupted after it began
 * setting the file aside leaves the directory refused with
 * StorageRestoreInterrupted until a restore completes. */
CREST_API crest_status_t CREST_CALL crest_app_restore(const uint8_t* fingerprint, size_t length,
    const uint8_t* configuration, size_t configuration_length, crest_buffer_t* out_rejection);
/* Saves any accepted revision still pending, then closes the session file.
 * Clear the wake callback first. */
CREST_API crest_status_t CREST_CALL crest_app_destroy(uint64_t app);
/* OK: buffer = published changes (a count, then each change): the pending
 * batch first, as crest_app_drain would answer it, then the intent's own.
 * REJECTED: buffer = one rejection.
 * Engine commands the intent caused (crest_engine.h) have run when it returns,
 * unless the dispatch itself runs inside a binding's command.
 * A cloud sync intent is dispatched from the transport's thread, never the
 * host's: its buffer holds only its receipts, what it changed waits for the
 * next crest_app_drain, and the engine commands it caused run there. */
CREST_API crest_status_t CREST_CALL crest_app_dispatch(uint64_t app, const uint8_t* intent, size_t length, crest_buffer_t* out);
/* OK: buffer = the answer. REJECTED: buffer = one rejection. */
CREST_API crest_status_t CREST_CALL crest_app_query(uint64_t app, const uint8_t* query, size_t length, crest_buffer_t* out);
/* Answers, without an app, a query that reads no state (SamePage,
 * LanguagesMatching, TranslationChoice, ResolveAddress without a workspace),
 * as crest_app_query would.
 * VERSION_MISMATCH when the fingerprint is not this core's schema;
 * INTERNAL_ERROR for a query only an app answers. */
CREST_API crest_status_t CREST_CALL crest_core_answer(const uint8_t* fingerprint, size_t fingerprint_length,
    const uint8_t* query, size_t length, crest_buffer_t* out);
CREST_API void CREST_CALL crest_buffer_free(crest_buffer_t* buffer);

/* Changes the core starts itself, such as Saved, StorageFailed, what a session
 * command changed, and the WorkspaceOpened and WorkspaceClosed of each session
 * attached to the app, wait in a pending batch. The wake callback carries
 * nothing: it runs on whichever core thread published the change, never while
 * the core holds a lock, when the batch goes from empty to not empty and when
 * the core queues work that follows the host's turn. Answer it by draining, on
 * the host's own thread, on its next turn, then calling crest_app_end_turn. A
 * callback set while changes wait is called at once. NULL removes the
 * callback; when set_wake returns, no earlier callback is still running. */
typedef void (CREST_CALL *crest_wake_t)(void* context);
CREST_API crest_status_t CREST_CALL crest_app_set_wake(uint64_t app, crest_wake_t callback, void* context);
/* OK: buffer = the pending changes, oldest first (a count, then each change).
 * Engine commands a cloud sync intent caused have run when it returns. */
CREST_API crest_status_t CREST_CALL crest_app_drain(uint64_t app, crest_buffer_t* out);
/* The host finished a turn of its thread: the drain a wake asked for has run.
 * Work queued to follow the turn, such as sync staging, may start, so the
 * edits one turn makes stage once. A drain inside a turn does not end it. */
CREST_API crest_status_t CREST_CALL crest_app_end_turn(uint64_t app);
/* Blocks until every sync stage of the session the app keeps in its file that
 * was requested before the call has committed, failed or been superseded,
 * without waiting for the host's turn or a coalescing delay; OK at once while
 * the file holds no session. It takes no lock the host's calls wait for, but
 * it blocks: never call it on the host's UI thread. */
CREST_API crest_status_t CREST_CALL crest_app_settle_sync(uint64_t app);

#ifdef __cplusplus
} /* extern "C" */
#endif
#endif /* CREST_APP_H */
