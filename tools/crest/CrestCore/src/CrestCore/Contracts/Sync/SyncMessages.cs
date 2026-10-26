namespace CrestCore.Contracts;

#region Intents

/// A record the cloud saved, at the version it saved.
public sealed record UploadedRecord(SyncRecordReference Record, SyncVersion Version);

#endregion

#region Queries

/// The records that wait to upload, in the order of their record names. None
/// while the stored session is the disposable seed a first launch made, which
/// never syncs.
public sealed record PendingUploadList(IReadOnlyList<SyncRecordReference> Records);

/// What the journal holds of the records a transport asked for: `Records`, each
/// one it holds and sends, in the order asked, and `Gone`, each one it no
/// longer holds, whose pending save the transport drops. A record it holds but
/// does not send, since no client would read it, is in neither, so its save
/// stays pending. While the stored session is the disposable seed a first
/// launch made, which never syncs, every record is gone.
public sealed record UploadBatch(IReadOnlyList<SyncRecord> Records, IReadOnlyList<SyncRecordReference> Gone);

#endregion

#region Changes

/// The session's sync journal changed: the core staged the session's accepted
/// edits, took a merge or an acknowledged upload, or attached the journal it
/// loaded. When the session keeps a file the journal is on disk with them. The
/// journal holds `Records` records, and `PendingRecords` of them wait to
/// upload. The cloud transport schedules an upload when it hears this.
public sealed record SyncJournalChanged(Guid WorkspaceId, int PendingRecords, int Records) : Change;

/// The receipt of a cloud intent that left records out: `Unreadable` records
/// no client of this build's schema reads, and `FromNewerBuild` records a
/// newer build wrote for a schema this build does not know. Nothing else about
/// the intent changes; the transport tells the person, and that updating Crest
/// on this device reads the second kind.
public sealed record SyncRecordsSkipped(int Unreadable, int FromNewerBuild) : Change;

/// The core could not stage the session's accepted edits for sync. The journal
/// is as it was; the next staged edit reports `SyncJournalChanged`.
public sealed record SyncStagingFailed(Guid WorkspaceId, SyncStagingFailure Reason) : Change;

#endregion

#region Rejections

/// The core cannot take the records the cloud sent, for the reason `Flaw`
/// names, about the record, tab, Space or profile `Subject` names when there is
/// one. Nothing changed.
public sealed record InvalidSyncRecords(SyncRecordFlaw Flaw, Guid? Subject) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Crest couldn’t apply the latest changes from iCloud.";

    #endregion
}

/// A command whose sync journal is saved with it could not stage that journal,
/// so the core refused the command and changed nothing.
public sealed record SyncStagingRefused(SyncStagingFailure Reason) : Rejection;

#endregion

#region Models

/// Whether this device's journal and the cloud hold the same content: the same
/// records, each in the same Space with an equivalent payload or tombstone.
/// Versions do not count, and of two cloud records with one identity the later
/// counts. `DeviceRecords` and `CloudRecords` count every record each holds,
/// tombstones included; `DeviceSpaces` and `CloudSpaces` count the Spaces each
/// keeps. A device whose session is the disposable seed a first launch made
/// holds nothing.
public sealed record CloudContentComparison(bool Matches, int DeviceRecords, int CloudRecords, int DeviceSpaces, int CloudSpaces);

/// One synced record as the transport carries it: its kind and identity, the
/// Space it belongs to, the version that wrote it, the oldest CloudKit schema
/// whose clients read it whole, and its body, which is its tombstone when
/// `IsTombstone` and its payload otherwise. The body is the CloudKit field as
/// the cloud stores it, with dates in seconds since 1970, and only the core
/// reads or writes it.
public sealed record SyncRecord(SyncRecordKind Kind, Guid Id, Guid SpaceId, SyncVersion Version, int Schema, byte[] Body, bool IsTombstone);

/// One synced record by identity: its kind, and the identity it has as that
/// kind. A tab and the archive entry it becomes share an identity, so the kind
/// tells them apart.
public sealed record SyncRecordReference(SyncRecordKind Kind, Guid Id);

#endregion
