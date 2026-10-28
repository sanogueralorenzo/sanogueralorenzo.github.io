namespace CrestCore.Contracts;

#region Intents

/// What an installed release kept in its defaults, exactly as the host read it:
/// the session without its history or images (`Core`), the whole-graph session
/// the releases before that split wrote (`WholeGraph`), each Space's history
/// beside `Core`, and the sync journal. The core decodes all of it. When `Core`
/// is present it is the installed session and `WholeGraph` is ignored.
public sealed record LegacySession(byte[]? Core, byte[]? WholeGraph, IReadOnlyList<LegacyHistory> History, byte[]? Journal);

/// One Space's history as an installed release kept it beside the session.
public sealed record LegacyHistory(Guid SpaceId, byte[] Entries);

#endregion

#region Queries

/// <summary>The newest file revision not yet on disk, which a later <c>Saved</c>
/// names; null when everything accepted is saved or the core keeps nothing.</summary>
public sealed record PendingSaveRevision(long? Revision);

#endregion

#region Changes

/// Everything the core handed its session file up to file revision `Revision`
/// is on disk: the stored session's edits and this device's saved windows.
public sealed record Saved(long Revision) : Change;

/// The session file holds its first session. `Favicons` are the images the
/// adopted session carried inside its tabs, for the host's image store; the
/// core keeps none of them.
public sealed record SessionAdopted(IReadOnlyList<TabFavicon> Favicons) : Change;

/// The image a tab shows, as the platform stored it.
public sealed record TabFavicon(Guid TabId, byte[] Image);

/// A save the core started on its own failed. The accepted session stays in
/// memory, and the next save writes everything that is not yet on disk.
public sealed record StorageFailed(StorageFailure Reason) : Change;

#endregion

#region Rejections

/// The recovery checkpoint cannot be restored: there is none, it does not hold
/// a complete session and journal, or it could not be put in place. A restore
/// that stops after it began setting the file aside leaves the restore marker,
/// so the directory stays refused until a restore completes.
public sealed record RecoveryCheckpointUnusable(StorageFailure Reason) : Rejection;

/// A save the intent had to finish before returning failed. Nothing was
/// published, and the file is as it was.
public sealed record SaveFailed(StorageFailure Reason) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Crest couldn’t save this change. Try again.";

    #endregion
}

/// The stored session or its sync journal was written by a newer version of
/// the app, which this build must not overwrite.
public sealed record StorageFromNewerApp : Rejection;

/// A restore from the recovery checkpoint did not finish. The core refuses the
/// directory until the restore completes, so a partial restore can never
/// become a fresh session.
public sealed record StorageRestoreInterrupted : Rejection;

/// The stored session could not be opened. Nothing was written to it.
public sealed record StorageUnreadable(StorageFailure Reason) : Rejection;

#endregion

#region Models

/// Why the session's storage could not be read or written.
public enum StorageFailure {
    /// The disk has no room for the write.
    DiskFull,
    /// The file or its directory cannot be written.
    ReadOnly,
    /// Another connection held the file for longer than the core waits.
    Busy,
    /// The file is not a readable session: a damaged database, a missing part
    /// or a part that does not decode.
    Damaged,
    /// Any other failure to open, read or write the file.
    Unavailable
}

#endregion
