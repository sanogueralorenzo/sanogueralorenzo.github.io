using CrestCore.Contracts;

namespace CrestCore.Domain;

/// A rule that stored and synced data keep, which a `BrowserRuleException`
/// names when data read from the session file, the sync journal, the cloud
/// or an import breaks it. It never reaches the host: every reader of such
/// data turns it into the `Rejection` its caller is answered with, and a rule
/// the person's own actions could break is refused with a `Rejection` where
/// it is checked. A rule the sync journal keeps also says what breaking it
/// means for sync: reading the cloud's records and staging this device's
/// session share the journal's rules, and each answers them its own way.
public sealed class BrowserRule {
    #region Static Variables

    public static readonly BrowserRule DuplicateSyncRecord = new("duplicate_sync_record", recordFlaw: SyncRecordFlaw.DuplicateRecord);
    public static readonly BrowserRule InvalidDeletionIntent = new("invalid_deletion_intent");
    public static readonly BrowserRule InvalidFolderTree = new("invalid_folder_tree", recordFlaw: SyncRecordFlaw.InvalidFolderHierarchy);
    public static readonly BrowserRule InvalidIdentity = new("invalid_identity", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSavedDate = new("invalid_saved_date", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSavedIdentity = new("invalid_saved_identity", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSavedState = new("invalid_saved_state", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSavedUrl = new("invalid_saved_url", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSyncDate = new("invalid_sync_date", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSyncDeletion = new("invalid_sync_deletion", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSyncKind = new("invalid_sync_kind", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSyncPending = new("invalid_sync_pending");
    public static readonly BrowserRule InvalidSyncPlacement = new("invalid_sync_placement", recordFlaw: SyncRecordFlaw.MalformedRecord);
    public static readonly BrowserRule InvalidSyncRecord = new("invalid_sync_record", recordFlaw: SyncRecordFlaw.MalformedRecord);
    /// The journal has issued every version it can.
    public static readonly BrowserRule SyncClockExhausted = new("sync_clock_exhausted", stagingFailure: SyncStagingFailure.ClockExhausted);
    public static readonly BrowserRule SyncIdentityMismatch = new("sync_identity_mismatch", recordFlaw: SyncRecordFlaw.IdentityMismatch);
    /// More records than sync carries: too many in the cloud's batch, or in
    /// the session a stage writes.
    public static readonly BrowserRule SyncRecordLimit = new("sync_record_limit", recordFlaw: SyncRecordFlaw.TooManyRecords,
        stagingFailure: SyncStagingFailure.TooLarge);
    /// A journal larger than sync keeps.
    public static readonly BrowserRule SyncSizeLimit = new("sync_size_limit", stagingFailure: SyncStagingFailure.TooLarge);
    public static readonly BrowserRule VersionMismatch = new("version_mismatch");

    public static IReadOnlyList<BrowserRule> All { get; } = [
        DuplicateSyncRecord, InvalidDeletionIntent, InvalidFolderTree, InvalidIdentity, InvalidSavedDate, InvalidSavedIdentity,
        InvalidSavedState, InvalidSavedUrl, InvalidSyncDate, InvalidSyncDeletion, InvalidSyncKind, InvalidSyncPending,
        InvalidSyncPlacement, InvalidSyncRecord, SyncClockExhausted, SyncIdentityMismatch, SyncRecordLimit, SyncSizeLimit,
        VersionMismatch
    ];

    #endregion

    #region Variables

    /// The rule's stable spelling, which a failure's message carries.
    public string Code { get; }

    /// What the cloud's records are when reading them breaks the rule, or
    /// null when the rule names no flaw of theirs. Records that break a rule
    /// naming none are refused as a staging failure where the rule names one,
    /// and as unexpected otherwise.
    public SyncRecordFlaw? RecordFlaw { get; }

    /// Why a stage of this device's session fails when it breaks the rule,
    /// or null when breaking it means the session is one sync cannot carry.
    public SyncStagingFailure? StagingFailure { get; }

    #endregion

    #region Constructors

    private BrowserRule(string code, SyncRecordFlaw? recordFlaw = null, SyncStagingFailure? stagingFailure = null) {
        Code = code;
        RecordFlaw = recordFlaw;
        StagingFailure = stagingFailure;
    }

    #endregion
}
