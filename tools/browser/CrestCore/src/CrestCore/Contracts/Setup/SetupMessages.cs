namespace CrestCore.Contracts;

#region Queries

/// Where each password goes, in the order they were asked about.
public sealed record ImportPasswordRoutes(IReadOnlyList<ImportPasswordRoute> Routes);

/// The Spaces one password goes to, none when it goes nowhere.
public sealed record ImportPasswordRoute(IReadOnlyList<Guid> SpaceIds);

/// The setup a launch holds its windows back for until it finishes, or null
/// when it holds them back for none.
public sealed record LaunchSetupGate(SetupEntry? Setup);

#endregion

#region Changes

/// Whether this device has completed setup changed, or was read as the
/// device store adopted it.
public sealed record SetupCompletedChanged(bool Completed) : Change;

/// The manual setup this device holds changed, or ended when `Draft` is null.
public sealed record SetupDraftChanged(SetupDraft? Draft) : Change;

/// Setup over the workspace finished. The platform opens the Getting Started
/// guide in `GuideSpaceId`, the workspace's first Space, when it names one.
public sealed record SetupFinished(Guid WorkspaceId, Guid? GuideSpaceId) : Change;

/// Setup on this device changed, or ended when `Flow` is null.
public sealed record SetupFlowChanged(SetupFlowState? Flow) : Change;

/// Setup as it stands on this device, over the workspace `WorkspaceId`: how
/// the person arrived, the step they see and where Back and Next lead from it,
/// what setup is doing, the browsers offered and chosen, the import queue and
/// the browser it is on, the review of that browser, why setup could not go
/// on, what it did last, and whether finishing opens the Getting Started
/// guide. `OpensCrestFromWelcome` is whether the welcome offers to open Crest
/// rather than set it up, as it does once setup is done. `Look` is the look
/// the Spaces setup makes wear, which the stage and every preview follow.
public sealed record SetupFlowState(Guid WorkspaceId, SetupEntry Entry, SetupStep Step, SetupStep? BackStep, SetupStep? NextStep,
    SetupPhase Phase, IReadOnlyList<ImportSource> Offered, IReadOnlyList<ImportSource> Selected, SetupImportQueue? Queue,
    ImportSource? Source, SetupImportReview? Review, SetupFailure? Failure, SetupSummary? Summary, bool OpensGuide,
    bool OpensCrestFromWelcome, SetupLook Look);

/// Why setup could not go on, the browser it concerns, and the words of what
/// refused it, when something did.
public sealed record SetupFailure(SetupFailureReason Reason, ImportSource? Source, string? Detail);

/// What setup did last: the tabs, passwords and Spaces an import brought,
/// or the Spaces a manual setup created and the tabs it added.
public sealed record SetupSummary(bool IsImport, int TabCount, int PasswordCount, int SpaceCount);

#endregion

#region Rejections

/// The Space `SpaceId`, where the Getting Started guide opens, is locked.
public sealed record GuideSpaceLocked(Guid SpaceId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Unlock your first Space to open Getting Started.";

    #endregion
}

/// No manual setup is in progress on this device for the workspace.
public sealed record NoManualSetup : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Setup is no longer in progress. Start it again.";

    #endregion
}

/// Setup is not open on this device.
public sealed record NoSetup : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Setup is no longer open. Open it again.";

    #endregion
}

/// Setup is reading or importing a browser, so what it works on cannot change.
public sealed record SetupBusy : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Wait for setup to finish reading or importing.";

    #endregion
}

#endregion

#region Models

/// Where a password another browser keeps belongs: the profile it was saved
/// in and its site's host. The password itself never crosses for routing.
public sealed record ImportPasswordSource(string ProfileName, string Host);

#endregion
