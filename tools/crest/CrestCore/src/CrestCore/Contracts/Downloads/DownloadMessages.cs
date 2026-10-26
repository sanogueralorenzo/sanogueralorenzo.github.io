namespace CrestCore.Contracts;

#region Intents

/// One Space's download retention for the profile it uses. A null lifetime
/// keeps records forever.
public sealed record DownloadRetention(Guid ProfileId, TimeSpan? Lifetime);

#endregion

#region Queries

/// The action for one download and the throttle state its page and origin
/// carry into the next automatic download.
public sealed record AutomaticDownloadVerdict(AutomaticDownloadAction Action, bool HasAllowedAutomaticDownload);

/// A download's risk assessment and whether the person must confirm it.
public sealed record DownloadRiskVerdict(DownloadRiskAssessment Assessment, bool RequiresConfirmation);

#endregion

#region Changes

/// Whether to keep the file of the download `DownloadId` waits on the person:
/// the core's `Reasons` it looks dangerous, and the engine's `Warning` when the
/// engine warned about it. `SpaceId` is the Space it belongs to and
/// `SourceHost` the host it came from, when known.
public sealed record DownloadApprovalAsked(Guid PromptId, Guid DownloadId, Guid? SpaceId, string Filename,
    IReadOnlyList<DownloadRiskReason> Reasons, DownloadWarning? Warning, string? SourceHost) : Change;

/// Where the file of the download `DownloadId` goes waits on the platform: the
/// download folder of the Space `SpaceId`, or the person's choice when
/// `ForcesPrompt` asks for one or that Space asks every time.
public sealed record DownloadDestinationAsked(Guid PromptId, Guid DownloadId, Guid SpaceId, string SuggestedFilename,
    bool ForcesPrompt) : Change;

/// The engine download `DownloadId` began on the page `PageId`, so the window
/// showing that page can show it leaving for the downloads list, whichever
/// engine runs it. A download the engine restored from an earlier run, and one
/// no page of its Space started, begins without one.
public sealed record DownloadStarted(Guid DownloadId, Guid PageId) : Change;

/// A download record changed or began. `Position` is its place in the
/// newest-first list after the change.
public sealed record DownloadUpdated(DownloadState Download, int Position) : Change;

/// One download record owned by a browsing profile. `Failure` says why a
/// failed record stopped, when that is known; `Message` explains a canceled or
/// failed record in words its engine or platform gave. Both are null in every
/// other phase.
public sealed record DownloadState(Guid Id, Guid ProfileId, DateTimeOffset CreatedAt, string Filename, string? Destination,
    double Progress, DownloadTelemetry Telemetry, DownloadPhase Phase, DownloadFailure? Failure, string? Message,
    DownloadRiskAssessment? Risk, bool IsAcknowledged, bool CanPause = false, bool CanResume = false);

/// Download records that were cleared, expired or removed with their profile.
public sealed record DownloadsRemoved(IReadOnlyList<Guid> DownloadIds) : Change;

#endregion

#region Rejections

/// The ledger already holds `Limit` records.
public sealed record DownloadLimitReached(int Limit) : Rejection;

/// A download with this identity is already recorded.
public sealed record DuplicateDownload() : Rejection;

/// A download or its profile has an empty identity.
public sealed record InvalidDownloadIdentity() : Rejection;

/// Transfer telemetry, progress or a final byte count is negative or not a number.
public sealed record InvalidDownloadProgress() : Rejection;

/// A progress sample's estimator state or clock reading is not valid.
public sealed record InvalidDownloadSample() : Rejection;

/// A download's text field is empty or longer than its limit.
public sealed record InvalidDownloadText(DownloadTextField Field) : Rejection;

/// A download retention lifetime is negative.
public sealed record InvalidRetentionLifetime() : Rejection;

#endregion

#region Models

/// One published transfer reading: the estimator state to send with the next
/// sample, the row telemetry and a progress in [0, 1].
public sealed record DownloadProgressReading(DownloadTransferEstimator Estimator, DownloadTelemetry Telemetry, double Progress);

#endregion
