#define _POSIX_C_SOURCE 200809L
#include "crest_app.h"
#include "crest_contracts.h"
#include "crest_core.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

/* The union tag a buffer starts with: its LEB128 varint, which takes a second
 * byte from 128 on. `used` receives how many bytes it took. */
static uint32_t read_tag(const uint8_t* bytes, size_t length, size_t* used) {
    uint32_t tag = 0;
    size_t at = 0;
    for (unsigned shift = 0; at < length && shift < 32; shift += 7) {
        uint8_t next = bytes[at++];
        tag |= (uint32_t)(next & 0x7f) << shift;
        if ((next & 0x80) == 0) break;
    }
    *used = at;
    return tag;
}

static void app_boundary(void) {
    const uint8_t fingerprint[CREST_CONTRACTS_FINGERPRINT_LENGTH] = CREST_CONTRACTS_FINGERPRINT;
    uint8_t stale[CREST_CONTRACTS_FINGERPRINT_LENGTH];
    memcpy(stale, fingerprint, sizeof(stale)); stale[0] ^= 1;
    /* AppConfiguration(StorageDirectory: null, Platform: Desktop): the optional
     * string is absent, then the platform's index in DevicePlatform.All, then
     * the optional import names are absent. */
    const uint8_t memory_only[] = { 0, 0, 0 };
    uint64_t app = 0;
    crest_buffer_t buffer = { (uint8_t*)1, 1 };
    assert(crest_app_create(stale, sizeof(stale), memory_only, sizeof(memory_only), &app, &buffer) == CREST_VERSION_MISMATCH
        && app == 0 && buffer.bytes == NULL);
    assert(crest_app_create(fingerprint, sizeof(fingerprint), memory_only, sizeof(memory_only), &app, &buffer) == CREST_OK
        && app != 0 && buffer.bytes == NULL);
    /* A union tag no contract uses is malformed input, not a rejection: the
     * varint 16383, far past the last intent. */
    const uint8_t garbage[] = { 0xff, 0x7f, 0x01, 0x02 };
    assert(crest_app_dispatch(app, garbage, sizeof(garbage), &buffer) == CREST_INVALID_MESSAGE);
    assert(buffer.bytes == NULL && buffer.length == 0);
    /* SetAgents(false), with its LEB128 union tag and boolean payload. */
    uint8_t request[6];
    size_t request_length = 0;
    uint32_t tag = CREST_INTENT_SET_AGENTS;
    do {
        uint8_t next = (uint8_t)(tag & 0x7f);
        tag >>= 7;
        request[request_length++] = tag == 0 ? next : (uint8_t)(next | 0x80);
    } while (tag != 0);
    request[request_length++] = 0;
    assert(crest_app_dispatch(app, request, request_length, &buffer) == CREST_OK);
    /* Agents are already disabled: a change list with a count of zero. */
    assert(buffer.bytes != NULL && buffer.length == 1 && buffer.bytes[0] == 0);
    crest_buffer_free(&buffer);
    assert(buffer.bytes == NULL && buffer.length == 0);
    crest_buffer_free(&buffer);
    /* System passkeys require the managed capability before device authorization applies. */
    uint8_t passkeys[] = { CREST_QUERY_PASSKEY_ACCESS, 0, 0, 0 };
    assert(crest_app_query(app, passkeys, sizeof(passkeys), &buffer) == CREST_OK);
    assert(buffer.length == 1 && buffer.bytes[0] == 0);
    crest_buffer_free(&buffer);
    passkeys[1] = 1;
    assert(crest_app_query(app, passkeys, sizeof(passkeys), &buffer) == CREST_OK);
    assert(buffer.length == 1 && buffer.bytes[0] == 3);
    crest_buffer_free(&buffer);
    assert(crest_app_destroy(app) == CREST_OK);
    assert(crest_app_dispatch(app, request, request_length, &buffer) == CREST_INVALID_HANDLE);
    assert(crest_app_destroy(app) == CREST_INVALID_HANDLE);
}
static const char* space_id = "44444444-4444-4444-4444-444444444444";
static const char* profile_id = "55555555-5555-5555-5555-555555555555";
/* A byte string: its LEB128 length, then the bytes. */
static size_t put_bytes(uint8_t* output, size_t at, size_t capacity, const char* bytes, size_t length) {
    size_t remaining = length;
    do {
        assert(at < capacity);
        uint8_t next = (uint8_t)(remaining & 0x7f);
        remaining >>= 7;
        output[at++] = remaining == 0 ? next : (uint8_t)(next | 0x80);
    } while (remaining != 0);
    assert(at + length <= capacity);
    memcpy(output + at, bytes, length);
    return at + length;
}
/* WorkspaceKind members travel as their index in WorkspaceKind.All. */
enum { persistent_kind = 0, private_kind = 1, borrowed_kind = 2 };
/* OpenWorkspace: its tag, the kind, then the seed: a presence byte and, when
 * present, a SessionState's fields alone, as a platform sends a record the
 * core resolves values of. */
/* A union tag: its LEB128 varint, which takes a second byte from 128 on.
 * Answers how many bytes it took. */
static size_t put_tag(uint8_t* output, uint32_t tag) {
    size_t at = 0;
    do {
        uint8_t next = (uint8_t)(tag & 0x7f);
        tag >>= 7;
        output[at++] = tag == 0 ? next : (uint8_t)(next | 0x80);
    } while (tag != 0);
    return at;
}
static size_t open_workspace(uint8_t* output, size_t capacity, uint8_t kind, const uint8_t* seed, size_t length) {
    assert(capacity >= 4 + length);
    size_t at = put_tag(output, CREST_INTENT_OPEN_WORKSPACE);
    output[at++] = kind;
    output[at++] = seed != NULL;
    if (seed != NULL) memcpy(output + at, seed, length);
    return at + length;
}
/* A SessionState seed of one Space named Reading, the Space all 0x44 with the
 * profile all 0x55, with no tabs. Unless
 * `deleted` is 0, it also records the deletion of the Space all `deleted`. */
static size_t session_seed(uint8_t* output, size_t capacity, uint8_t deleted) {
    static const uint8_t settings[] = {
        7, 'R', 'e', 'a', 'd', 'i', 'n', 'g',
        0, 0, 0, 0, /* balanced blocking and the first history, archive and download retention */
        0, 0        /* GitHub not dismissed, no custom Space color */
    };
    size_t at = 0;
    assert(capacity >= 1 + 37 + sizeof(settings) + 4 + 48);
    output[at++] = 1;
    memset(output + at, 0x44, 16);
    memset(output + at + 16, 0x55, 16);
    memcpy(output + at + 32, settings, sizeof(settings));
    at += 32 + sizeof(settings);
    /* No folders, tabs, archived tabs or history, then no seed marker. */
    memset(output + at, 0, 5);
    at += 5;
    /* The Space deletions: each its operation, Space and profile. */
    output[at++] = deleted != 0;
    if (deleted != 0) {
        memset(output + at, 0x77, 16);
        memset(output + at + 16, deleted, 16);
        memset(output + at + 32, 0x78, 16);
        at += 48;
    }
    /* No app preferences. */
    output[at++] = 0;
    return at;
}
/* The workspace a WorkspaceOpened at `at` names: the 16 RFC 4122 bytes after
 * its tag. Its kind follows them. */
static void opened_workspace(const crest_buffer_t* buffer, size_t at, uint8_t workspace[16], uint8_t kind) {
    assert(at + 18 <= buffer->length && buffer->bytes[at] == CREST_CHANGE_WORKSPACE_OPENED);
    assert(buffer->bytes[at + 17] == kind);
    memcpy(workspace, buffer->bytes + at + 1, 16);
}
/* Whether a SyncJournalChanged for `workspace` is at `at`: its tag, the
 * workspace it names, then the journal's pending and record counts, two
 * int32s. */
static int journal_changed(const crest_buffer_t* buffer, size_t at, const uint8_t workspace[16]) {
    return at + 25 <= buffer->length && buffer->bytes[at] == CREST_CHANGE_SYNC_JOURNAL_CHANGED
        && memcmp(buffer->bytes + at + 1, workspace, 16) == 0;
}
/* Opens a workspace of `kind` from `seed` in `app` and answers its identity:
 * the answer is its WorkspaceOpened alone. */
static void open_seeded(uint64_t app, uint8_t kind, const uint8_t* seed, size_t length, uint8_t workspace[16]) {
    uint8_t intent[1100];
    crest_buffer_t buffer = { NULL, 0 };
    size_t size = open_workspace(intent, sizeof(intent), kind, seed, length);
    assert(crest_app_dispatch(app, intent, size, &buffer) == CREST_OK && buffer.bytes[0] == 1);
    opened_workspace(&buffer, 1, workspace, kind);
    crest_buffer_free(&buffer);
}
/* The core gives each workspace it opens its identity: from a seed, from the
 * template of a private one, or by borrowing a Space; closing an owner closes
 * its borrowers first. */
static void session_boundary(void) {
    const uint8_t fingerprint[CREST_CONTRACTS_FINGERPRINT_LENGTH] = CREST_CONTRACTS_FINGERPRINT;
    const uint8_t memory_only[] = { 0, 0, 0 };
    uint64_t app = 0;
    crest_buffer_t buffer = { NULL, 0 };
    assert(crest_app_create(fingerprint, sizeof(fingerprint), memory_only, sizeof(memory_only), &app, &buffer) == CREST_OK);
    uint8_t seed[256], intent[300];
    /* A seed the core cannot hold is refused with the flaw it has: its Space
     * deletion names a Space it does not hold (SessionFlaw.UnknownDeletion is 5). */
    size_t size = session_seed(seed, sizeof(seed), 0x66);
    size_t length = open_workspace(intent, sizeof(intent), persistent_kind, seed, size);
    assert(crest_app_dispatch(app, intent, length, &buffer) == CREST_REJECTED);
    assert(buffer.length == 2 && buffer.bytes[0] == CREST_REJECTION_INVALID_SESSION && buffer.bytes[1] == 5);
    crest_buffer_free(&buffer);
    /* A borrowed workspace opens only by borrowing. */
    size = session_seed(seed, sizeof(seed), 0);
    length = open_workspace(intent, sizeof(intent), borrowed_kind, seed, size);
    assert(crest_app_dispatch(app, intent, length, &buffer) == CREST_REJECTED);
    assert(buffer.length == 2 && buffer.bytes[0] == CREST_REJECTION_BORROWED_WORKSPACE_REQUIRES_SPACE
        && buffer.bytes[1] == borrowed_kind);
    crest_buffer_free(&buffer);

    uint8_t workspace[16], private_workspace[16], borrowed[16];
    open_seeded(app, persistent_kind, seed, size, workspace);
    open_seeded(app, private_kind, NULL, 0, private_workspace);
    assert(memcmp(workspace, private_workspace, 16) != 0);
    /* BorrowSpace: its tag, the owner, the Space (all 0x44) and its profile
     * (all 0x55). */
    uint8_t borrow[49] = { CREST_INTENT_BORROW_SPACE };
    memcpy(borrow + 1, workspace, 16);
    memset(borrow + 17, 0x44, 16);
    memset(borrow + 33, 0x55, 16);
    assert(crest_app_dispatch(app, borrow, sizeof(borrow), &buffer) == CREST_OK && buffer.bytes[0] == 1);
    opened_workspace(&buffer, 1, borrowed, borrowed_kind);
    crest_buffer_free(&buffer);

    /* CloseWorkspace: its tag and the workspace. The borrower closes first; a
     * workspace that is not open publishes nothing. */
    uint8_t closing[17] = { CREST_INTENT_CLOSE_WORKSPACE };
    memcpy(closing + 1, workspace, 16);
    assert(crest_app_dispatch(app, closing, sizeof(closing), &buffer) == CREST_OK);
    assert(buffer.length == 35 && buffer.bytes[0] == 2);
    assert(buffer.bytes[1] == CREST_CHANGE_WORKSPACE_CLOSED && memcmp(buffer.bytes + 2, borrowed, 16) == 0);
    assert(buffer.bytes[18] == CREST_CHANGE_WORKSPACE_CLOSED && memcmp(buffer.bytes + 19, workspace, 16) == 0);
    crest_buffer_free(&buffer);
    assert(crest_app_dispatch(app, closing, sizeof(closing), &buffer) == CREST_OK);
    assert(buffer.length == 1 && buffer.bytes[0] == 0);
    crest_buffer_free(&buffer);
    assert(crest_app_destroy(app) == CREST_OK);
}
static volatile int storage_wakes = 0;
static void count_wake(void* context) {
    assert(context == &storage_wakes);
    storage_wakes++;
}
/* AppConfiguration with a storage directory: presence, varint length, UTF-8. */
static size_t storage_configuration(const char* directory, uint8_t* output, size_t capacity) {
    size_t length = strlen(directory);
    assert(length < 128 && length + 4 <= capacity);
    output[0] = 1;
    output[1] = (uint8_t)length;
    memcpy(output + 2, directory, length);
    /* The platform: Desktop, the first of DevicePlatform.All. */
    output[length + 2] = 0;
    /* The import names are absent. */
    output[length + 3] = 0;
    return length + 4;
}
/* Saved(Revision: 1): its tag, then the file revision as a little-endian
 * int64. An adoption hands the file its first revision. The storage worker
 * announces the save on its own thread, so the Saved lands in whichever
 * answer or drain collects the pending changes next. */
static const uint8_t first_save[9] = { CREST_CHANGE_SAVED, 1 };
static int is_first_save(const crest_buffer_t* buffer, size_t at) {
    return at + sizeof(first_save) <= buffer->length && memcmp(buffer->bytes + at, first_save, sizeof(first_save)) == 0;
}
/* The number of changes in a change list that holds only Saved(Revision: 1). */
static int first_saves(const crest_buffer_t* buffer) {
    assert(buffer->length >= 1 && buffer->bytes[0] < 0x80);
    size_t count = buffer->bytes[0];
    assert(buffer->length == 1 + count * sizeof(first_save));
    for (size_t index = 0; index < count; index++) assert(is_first_save(buffer, 1 + index * sizeof(first_save)));
    return (int)count;
}
/* The core opens and owns session.sqlite: an empty file holds no session to
 * open, the first session is adopted once, the save it starts wakes the host,
 * and the workspace that keeps the file opens once per launch. A directory
 * without a recovery checkpoint cannot be restored. */
static void storage_boundary(void) {
    const uint8_t fingerprint[CREST_CONTRACTS_FINGERPRINT_LENGTH] = CREST_CONTRACTS_FINGERPRINT;
    /* The core creates the directory it is given. */
    char directory[96];
    snprintf(directory, sizeof(directory), "/tmp/crest-native-abi-%ld-%ld", (long)getpid(), (long)time(NULL));
    uint8_t configuration[160];
    size_t configured = storage_configuration(directory, configuration, sizeof(configuration));
    uint64_t app = 0;
    crest_buffer_t buffer = { NULL, 0 };
    assert(crest_app_create(fingerprint, sizeof(fingerprint), configuration, configured, &app, &buffer) == CREST_OK && app != 0);
    /* With no session in the file there is no stage to settle. */
    assert(crest_app_settle_sync(app) == CREST_OK);
    assert(crest_app_settle_sync(0) == CREST_INVALID_HANDLE);
    /* OpenWorkspace for the file's session, without a seed. */
    uint8_t stored[4];
    size_t opening_stored = open_workspace(stored, sizeof(stored), persistent_kind, NULL, 0);
    assert(crest_app_dispatch(app, stored, opening_stored, &buffer) == CREST_REJECTED);
    assert(buffer.length == 1 && buffer.bytes[0] == CREST_REJECTION_NO_STORED_SESSION);
    crest_buffer_free(&buffer);
    assert(crest_app_set_wake(app, count_wake, (void*)&storage_wakes) == CREST_OK);
    char json[512];
    int size = snprintf(json, sizeof(json),
        "{\"spaces\":[{\"id\":{\"rawValue\":\"%s\"},\"profile\":{\"id\":\"%s\"},\"name\":\"Stored\","
        "\"tabs\":[],\"folders\":[],\"history\":[],\"archivedTabs\":[]}]}", space_id, profile_id);
    assert(size > 0 && (size_t)size < sizeof(json));
    /* AdoptLegacySession: the installed release kept the session whole
     * (Core absent, WholeGraph present, no history parts, no journal), and no
     * seed stands in for it. */
    uint8_t adoption[1100];
    size_t adopted = 0;
    adoption[adopted++] = CREST_INTENT_ADOPT_LEGACY_SESSION;
    adoption[adopted++] = 0;
    adoption[adopted++] = 1;
    adopted = put_bytes(adoption, adopted, sizeof(adoption), json, (size_t)size);
    adoption[adopted++] = 0;
    adoption[adopted++] = 0;
    adoption[adopted++] = 0;
    assert(crest_app_dispatch(app, adoption, adopted, &buffer) == CREST_OK);
    /* SessionAdopted, carrying no images. The answer starts with the changes
     * the core announced while the adoption ran, so the adoption's Saved comes
     * first when the save finished in time. */
    assert(buffer.length >= 3 && buffer.bytes[0] < 0x80);
    int saves = is_first_save(&buffer, 1);
    size_t adopted_at = 1 + (saves ? sizeof(first_save) : 0);
    assert(buffer.bytes[0] == 1 + saves && buffer.length == adopted_at + 2);
    assert(buffer.bytes[adopted_at] == CREST_CHANGE_SESSION_ADOPTED && buffer.bytes[adopted_at + 1] == 0);
    crest_buffer_free(&buffer);
    /* The file holds a session now: a second adoption changes nothing. Only
     * the first adoption's save can still arrive with its answer. */
    assert(crest_app_dispatch(app, adoption, adopted, &buffer) == CREST_OK);
    saves += first_saves(&buffer);
    crest_buffer_free(&buffer);
    for (int attempt = 0; attempt < 1000 && storage_wakes == 0; attempt++) {
        struct timespec pause = { 0, 5000000 };
        nanosleep(&pause, NULL);
    }
    /* The core wakes the host for the save it announced on its own thread. */
    assert(storage_wakes >= 1);
    /* The save is announced once, in an answer above or in a drain. */
    for (int attempt = 0; attempt < 1000 && saves == 0; attempt++) {
        assert(crest_app_drain(app, &buffer) == CREST_OK);
        saves += first_saves(&buffer);
        crest_buffer_free(&buffer);
        struct timespec pause = { 0, 5000000 };
        if (saves == 0) nanosleep(&pause, NULL);
    }
    assert(saves == 1);
    /* The stored session's workspace, which a saved window shows, then what
     * the journal it attached holds. Opening it again while it is open
     * publishes the same identity again, and nothing else. */
    uint8_t workspace[16] = { 0 }, again[16] = { 0 };
    assert(crest_app_dispatch(app, stored, opening_stored, &buffer) == CREST_OK && buffer.bytes[0] == 2);
    opened_workspace(&buffer, 1, workspace, persistent_kind);
    assert(journal_changed(&buffer, buffer.length - 25, workspace));
    crest_buffer_free(&buffer);
    assert(crest_app_dispatch(app, stored, opening_stored, &buffer) == CREST_OK && buffer.bytes[0] == 1);
    opened_workspace(&buffer, 1, again, persistent_kind);
    crest_buffer_free(&buffer);
    assert(memcmp(workspace, again, 16) == 0);
    /* Ending the turn starts the launch stage of the workspace that opened,
     * which the host hears about. */
    assert(crest_app_end_turn(app) == CREST_OK);
    int staged = 0;
    for (int attempt = 0; attempt < 1000 && !staged; attempt++) {
        assert(crest_app_drain(app, &buffer) == CREST_OK);
        staged = buffer.length > 2 && buffer.bytes[0] == 1 && buffer.bytes[1] == CREST_CHANGE_SYNC_JOURNAL_CHANGED;
        assert(staged || (buffer.length == 1 && buffer.bytes[0] == 0));
        crest_buffer_free(&buffer);
        struct timespec pause = { 0, 5000000 };
        if (!staged) nanosleep(&pause, NULL);
    }
    assert(staged);
    /* Every stage requested so far has settled, so settling returns at once. */
    assert(crest_app_settle_sync(app) == CREST_OK);
    assert(crest_app_set_wake(app, NULL, NULL) == CREST_OK);
    /* OpenWindow: its tag, the window, the workspace, Saved, no window to copy,
     * no Space to show, no tabs to show, RestoresTabs. It answers one
     * WindowChanged. */
    uint8_t opening[42] = { 0 };
    size_t window_tag = put_tag(opening, CREST_INTENT_OPEN_WINDOW);
    memset(opening + window_tag, 0x42, 16);
    memcpy(opening + window_tag + 16, workspace, 16);
    opening[window_tag + 32] = 1; opening[window_tag + 36] = 1;
    assert(crest_app_dispatch(app, opening, window_tag + 37, &buffer) == CREST_OK);
    assert(buffer.length > 2 && buffer.bytes[0] == 1 && buffer.bytes[1] == CREST_CHANGE_WINDOW_CHANGED);
    crest_buffer_free(&buffer);
    assert(crest_app_destroy(app) == CREST_OK);

    /* A second launch opens what the first one saved, then what its journal
     * holds. Its launch save, which finds nothing to change, may be announced
     * before WorkspaceOpened, before SyncJournalChanged or after it: a Saved
     * is its tag and an int64. */
    assert(crest_app_create(fingerprint, sizeof(fingerprint), configuration, configured, &app, &buffer) == CREST_OK);
    assert(crest_app_dispatch(app, stored, opening_stored, &buffer) == CREST_OK);
    size_t at = 1, announced = 2;
    for (; at < buffer.length && buffer.bytes[at] == CREST_CHANGE_SAVED; at += 9) announced++;
    assert(buffer.bytes[0] == announced || buffer.bytes[0] == announced + 1);
    opened_workspace(&buffer, at, again, persistent_kind);
    assert(journal_changed(&buffer, buffer.length - 25, again)
        || (journal_changed(&buffer, buffer.length - 34, again) && buffer.bytes[buffer.length - 9] == CREST_CHANGE_SAVED));
    crest_buffer_free(&buffer);
    assert(crest_app_settle_sync(app) == CREST_OK);
    assert(crest_app_destroy(app) == CREST_OK);

    /* A file that is not a session is refused with a rejection, untouched. */
    char path[256];
    snprintf(path, sizeof(path), "%s/session.sqlite", directory);
    FILE* file = fopen(path, "wb");
    assert(file != NULL && fputs("not a session", file) >= 0 && fclose(file) == 0);
    assert(crest_app_create(fingerprint, sizeof(fingerprint), configuration, configured, &app, &buffer) == CREST_REJECTED
        && app == 0 && buffer.bytes != NULL);
    size_t used = 0;
    assert(read_tag(buffer.bytes, buffer.length, &used) == CREST_REJECTION_STORAGE_UNREADABLE);
    crest_buffer_free(&buffer);
    /* The second launch kept a recovery checkpoint, since the file held a
     * session and its staged journal; without one a restore is refused. */
    char checkpoint[256];
    snprintf(checkpoint, sizeof(checkpoint), "%s/session.recovery.sqlite", directory);
    assert(remove(checkpoint) == 0);
    assert(crest_app_restore(fingerprint, sizeof(fingerprint), configuration, configured, &buffer) == CREST_REJECTED
        && buffer.bytes != NULL);
    assert(read_tag(buffer.bytes, buffer.length, &used) == CREST_REJECTION_RECOVERY_CHECKPOINT_UNUSABLE);
    crest_buffer_free(&buffer);
    char command[320];
    snprintf(command, sizeof(command), "rm -rf '%s'", directory);
    assert(system(command) == 0);
}
int main(void) {
    assert(crest_core_abi_version() == CREST_ABI_VERSION);
    app_boundary();
    session_boundary();
    storage_boundary();
    puts("Native ABI buffer ownership, handle, session and storage checks passed.");
    return 0;
}
