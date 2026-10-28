namespace CrestCore.Contracts;

#region Queries

/// The fields the device store keeps of the records asked for; a record it
/// keeps none of is left out.
public sealed record CloudRecordFieldList(IReadOnlyList<CloudRecordFields> Records);

#endregion

#region Changes

/// A merge of downloaded records began as `MergeId`.
public sealed record CloudMergeBegan(long MergeId) : Change;

/// The cloud transport's state after the intent that answered it.
public sealed record CloudTransportChanged(CloudTransportState State) : Change;

#endregion

#region Rejections

/// The cloud transport state an installed release kept does not read. Nothing
/// was adopted.
public sealed record LegacyCloudStateUnreadable : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Crest couldn’t read the iCloud sync state an earlier version saved.";

    #endregion
}

/// No merge of downloaded records under way on this device is named `MergeId`.
public sealed record UnknownCloudMerge(long MergeId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Crest lost track of an iCloud download it was applying.";

    #endregion
}

#endregion

#region Models

/// The server's fields of one uploaded record, as the transport archived
/// them, and the record schema the server copy carries, which the archive
/// leaves out. The transport uploads over them, so a save targets the
/// server's version.
public sealed record CloudRecordFields(string RecordName, byte[] Fields, int? SchemaVersion);

/// The cloud transport's state on this device. `RequiresFullPull` holds while
/// a download may have advanced the cursor past content the session never
/// took, until a full snapshot is applied. `AwaitsAccountDecision` pauses
/// sync after the account changed until the person chooses which copy to
/// keep. `OverwritesCloud` holds after the person chose this device's copy,
/// until every record it staged has uploaded: meanwhile fetched content is
/// not merged and a record the server changed is uploaded again.
/// `EngineState` is the sync engine's own saved state, which only the
/// transport reads. `IsAdopted` tells whether the state an installed
/// release kept in its file was carried into the device store yet.
public sealed record CloudTransportState(
    bool RequiresFullPull,
    bool AwaitsAccountDecision,
    bool OverwritesCloud,
    byte[]? EngineState,
    bool IsAdopted);

#endregion
