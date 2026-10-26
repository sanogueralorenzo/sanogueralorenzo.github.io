namespace CrestCore.Contracts;

#region Queries



#endregion

#region Changes

/// The import on this device changed, or ended when `Flow` is null.
public sealed record ImportFlowChanged(ImportFlowState? Flow) : Change;

/// A Settings import: its workspace, current stage, offered and selected browsers,
/// queue, review, failure, and most recent completed import.
public sealed record ImportFlowState(Guid WorkspaceId, ImportStep Step,
    ImportPhase Phase, IReadOnlyList<ImportSource> Offered, IReadOnlyList<ImportSource> Selected, ImportQueue? Queue,
    ImportSource? Source, ImportReview? Review, ImportFailure? Failure, ImportSummary? Summary);

/// Why setup could not go on, the browser it concerns, and the words of what
/// refused it, when something did.
public sealed record ImportFailure(ImportFailureReason Reason, ImportSource? Source, string? Detail);

public sealed record ImportSummary(int TabCount, int SpaceCount);

#endregion

#region Rejections

/// Setup is not open on this device.
public sealed record NoBrowserImport : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Import is no longer open. Open it again.";

    #endregion
}

/// Setup is reading or importing a browser, so what it works on cannot change.
public sealed record BrowserImportBusy : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Wait for the import to finish.";

    #endregion
}

#endregion

#region Models


#endregion
