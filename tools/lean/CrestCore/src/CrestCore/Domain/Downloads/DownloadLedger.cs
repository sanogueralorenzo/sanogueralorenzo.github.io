using CrestCore.Contracts;

namespace CrestCore.Domain;

/// The process-local record of this run's downloads, newest first.
///
/// Engines report transfer events and the ledger decides what each event
/// means for the record: live transfers accept progress, destinations, risk
/// verdicts and a final outcome; a blocked automatic download may only be
/// retried or failed; an interrupted transfer resumes only after the person
/// requests recovery supported by its engine. An event that does not apply to the record's phase is ignored and
/// answers null, so a late engine callback cannot revive a record. A broken
/// rule throws `Rejected`. Nothing here is persisted or synced. Callers
/// serialize access.
public sealed class DownloadLedger {
    #region Variables

    public const int MaximumItems = 10_000;

    private readonly List<DownloadState> items = [];

    public IReadOnlyList<DownloadState> Items => items;

    #endregion

    #region Actions - Ordering

    /// Records a new download as preparing, ahead of every existing record. The
    /// caller supplies the identity and creation time so a retried call is
    /// deterministic. A download restored by an engine starts acknowledged.
    public DownloadState Begin(Guid id, Guid profileId, string filename, DateTimeOffset createdAt, bool isAcknowledged) {
        if (id == Guid.Empty || profileId == Guid.Empty) throw new Rejected(new InvalidDownloadIdentity());
        DownloadTextField.Filename.Validate(filename);
        if (IndexOf(id) >= 0) throw new Rejected(new DuplicateDownload());
        if (items.Count >= MaximumItems) throw new Rejected(new DownloadLimitReached(MaximumItems));
        var item = new DownloadState(id, profileId, createdAt, filename, null, 0, DownloadTelemetry.Empty,
            DownloadPhase.Preparing, null, null, null, isAcknowledged);
        items.Insert(0, item);
        return item;
    }

    public int IndexOf(Guid id) => items.FindIndex(item => item.Id == id);

    #endregion

    #region Actions - Transfers

    /// The destination names the file, so the record's filename follows it.
    public DownloadState? SetDestination(Guid id, string destination, string filename) {
        DownloadTextField.Destination.Validate(destination);
        DownloadTextField.Filename.Validate(filename);
        return UpdateLive(id, item => item with { Destination = destination, Filename = filename, Phase = DownloadPhase.Downloading });
    }

    /// Progress never moves backwards while a transfer is live.
    public DownloadState? RecordTransfer(Guid id, DownloadTelemetry telemetry, double progress) {
        ArgumentNullException.ThrowIfNull(telemetry);
        if (!telemetry.IsValid || !double.IsFinite(progress)) throw new Rejected(new InvalidDownloadProgress());
        return UpdateLive(id, item => item with {
            Telemetry = telemetry,
            Progress = Math.Max(item.Progress, Math.Clamp(progress, 0, 1))
        });
    }

    /// Only the engine knows which transfers it can pause or recover. A
    /// terminal record never offers pause, and only a failed one may recover.
    public DownloadState? SetControls(Guid id, bool canPause, bool canResume) =>
        Update(id, item => item.CanPause != (canPause && item.Phase.IsTransferring)
            || item.CanResume != (canResume && item.Phase.AllowsResume),
            item => item with {
                CanPause = canPause && item.Phase.IsTransferring,
                CanResume = canResume && item.Phase.AllowsResume
            });

    /// The engine confirmed a requested recovery. Its next reading may start
    /// at zero when the server cannot continue the existing partial file.
    public DownloadState? Resume(Guid id) =>
        Update(id, item => item.Phase == DownloadPhase.Failed && item.CanResume, item => item with {
            Phase = DownloadPhase.Downloading,
            Progress = 0,
            Telemetry = DownloadTelemetry.Empty,
            Failure = null,
            Message = null,
            CanPause = false,
            CanResume = false
        });

    /// A download with any risk reason waits for approval under its sanitized name.
    public DownloadState? AssessRisk(Guid id, DownloadRiskAssessment assessment) {
        ArgumentNullException.ThrowIfNull(assessment);
        DownloadTextField.Filename.Validate(assessment.SanitizedFilename);
        return UpdateLive(id, item => item with {
            Filename = assessment.SanitizedFilename,
            Risk = assessment,
            Phase = assessment.Reasons.Count > 0 ? DownloadPhase.AwaitingApproval : item.Phase
        });
    }

    public DownloadState? AwaitApproval(Guid id) =>
        UpdateLive(id, item => item with { Phase = DownloadPhase.AwaitingApproval });

    public DownloadState? Finish(Guid id, long? finalByteCount) {
        if (finalByteCount < 0) throw new Rejected(new InvalidDownloadProgress());
        return UpdateLive(id, item => item with {
            Progress = 1,
            Telemetry = item.Telemetry.Stopped(finalByteCount, completed: true),
            Phase = DownloadPhase.Finished,
            CanPause = false,
            CanResume = false
        });
    }

    public DownloadState? Cancel(Guid id, string message) {
        DownloadTextField.Message.Validate(message);
        return UpdateLive(id, item => Stopped(item, DownloadPhase.Canceled, message));
    }

    /// A blocked automatic download may also fail, when its retry can no longer
    /// be replayed.
    /// A failure says why when it is known, and carries the engine's or
    /// platform's own words when it has them; it needs one of the two.
    public DownloadState? Fail(Guid id, DownloadFailure? reason, string? message) {
        if (message is not null || reason is null) DownloadTextField.Message.Validate(message ?? "");
        return Update(id, item => item.Phase.CanFail, item => Stopped(item, DownloadPhase.Failed, message) with { Failure = reason });
    }

    public DownloadState? BlockAutomaticDownload(Guid id) =>
        UpdateLive(id, item => Stopped(item, DownloadPhase.BlockedAutomaticDownload, null));

    /// Retrying a blocked automatic download starts the same record again from
    /// nothing and counts as news for the downloads badge.
    public DownloadState? Restart(Guid id) =>
        Update(id, item => item.Phase.CanRetry, item => item with {
            Destination = null,
            Progress = 0,
            Telemetry = DownloadTelemetry.Empty,
            Phase = DownloadPhase.Preparing,
            Failure = null,
            Message = null,
            Risk = null,
            IsAcknowledged = false,
            CanPause = false,
            CanResume = false
        });

    #endregion

    #region Actions - Acknowledgement

    /// Opening a profile's downloads acknowledges its records without clearing
    /// them. Returns the records that were newly acknowledged.
    public IReadOnlyList<DownloadState> AcknowledgeProfile(Guid profileId) {
        var acknowledged = new List<DownloadState>();
        for (int index = 0; index < items.Count; index++) {
            if (items[index].ProfileId != profileId || items[index].IsAcknowledged) continue;
            items[index] = items[index] with { IsAcknowledged = true };
            acknowledged.Add(items[index]);
        }
        return acknowledged;
    }

    #endregion

    #region Actions - Expiry

    /// Clearing removes only a record; files already written stay on disk. The
    /// caller refuses to clear a record whose transfer it still owns.
    public bool Remove(Guid id) {
        int index = IndexOf(id);
        if (index < 0) return false;
        items.RemoveAt(index);
        return true;
    }

    /// Deleting a profile's data removes every record it owns, live or not; the
    /// caller cancels the matching transfers.
    public IReadOnlyList<Guid> RemoveProfile(Guid profileId) => RemoveWhere(item => item.ProfileId == profileId);

    /// Removes records whose age strictly exceeds their profile's retention.
    /// When several Spaces share a profile the shortest retention wins; a
    /// profile with no limit keeps its records. Live transfers never expire.
    public IReadOnlyList<Guid> RemoveExpired(IReadOnlyList<DownloadRetention> retentions, DateTimeOffset now) {
        ArgumentNullException.ThrowIfNull(retentions);
        var lifetimes = new Dictionary<Guid, TimeSpan?>();
        foreach (var retention in retentions) {
            if (retention.Lifetime < TimeSpan.Zero) throw new Rejected(new InvalidRetentionLifetime());
            lifetimes[retention.ProfileId] = lifetimes.TryGetValue(retention.ProfileId, out var existing)
                ? Shorter(existing, retention.Lifetime)
                : retention.Lifetime;
        }
        return RemoveWhere(item => !item.Phase.IsLive && lifetimes.TryGetValue(item.ProfileId, out var lifetime)
            && lifetime is { } limit && now - item.CreatedAt > limit);
    }

    private static TimeSpan? Shorter(TimeSpan? existing, TimeSpan? proposed) =>
        existing is not { } current ? proposed : proposed is not { } next ? current : TimeSpan.FromTicks(Math.Min(current.Ticks, next.Ticks));

    private IReadOnlyList<Guid> RemoveWhere(Predicate<DownloadState> predicate) {
        IReadOnlyList<Guid> removed = [.. items.Where(item => predicate(item)).Select(item => item.Id)];
        items.RemoveAll(predicate);
        return removed;
    }

    #endregion

    #region Actions - Transitions

    private static DownloadState Stopped(DownloadState item, DownloadPhase phase, string? message) =>
        item with {
            Telemetry = item.Telemetry.Stopped(),
            Phase = phase,
            Failure = null,
            Message = message,
            CanPause = false,
            CanResume = false
        };

    private DownloadState? UpdateLive(Guid id, Func<DownloadState, DownloadState> transition) =>
        Update(id, item => item.Phase.IsLive, transition);

    private DownloadState? Update(Guid id, Func<DownloadState, bool> accepts, Func<DownloadState, DownloadState> transition) {
        int index = IndexOf(id);
        if (index < 0 || !accepts(items[index])) return null;
        items[index] = transition(items[index]);
        return items[index];
    }

    #endregion
}
