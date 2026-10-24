using System.Diagnostics;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

#region Types

/// What one engine download report needs: where it publishes what it changed,
/// where it hands the engine commands it causes, and the time it happens at.
internal sealed record EngineDownloadTurn(ChangeFeed Changes, Action<Engine, EngineCommand> Issue, DateTimeOffset Now);

#endregion

/// The downloads engines run, in the core's download ledger. Each belongs to
/// the Space its page lives in, or else the one Space its profile belongs to; a
/// download no Space the person may see can hold is cancelled. The core judges
/// each download's risk from the platform's facts before it asks where its
/// file goes, and a download the person must confirm is asked about first.
/// Where a file goes and whether to keep a file the core or the engine warned
/// about are prompts, which settle when answered or when their download ends.
/// The person's row actions reach the engine as commands. Nothing here is
/// saved or synced, and a download's source is kept only as its host, only
/// while the engine runs it.
internal sealed class EngineDownloads(Downloads downloads, Device device, Pages pages, IIdSource ids) {
    #region Types

    /// One engine download the ledger records.
    internal sealed class Tracked(Engine engine, Guid profileId, string engineId, Guid downloadId) {
        public Engine Engine { get; } = engine;
        public Guid ProfileId { get; } = profileId;
        public string EngineId { get; } = engineId;
        public Guid DownloadId { get; } = downloadId;
        public DownloadTransferEstimator? Estimator { get; set; }
        /// The engine still runs it; after it ends only a requested recovery
        /// can accept another transfer report.
        public bool IsLive { get; set; } = true;
        public bool ResumeRequested { get; set; }
        public EngineDownload? LastReport { get; set; }
        /// The warning the approval waiting on the person is about, or the
        /// blocked download a retry replays.
        public string? ApprovalToken { get; set; }
        /// The site's choices refused it, and it waits for the person to retry it.
        public bool IsBlocked { get; set; }
        /// Why the core judged it dangerous, and whether the person kept it
        /// knowing that.
        public IReadOnlyList<DownloadRiskReason> Reasons { get; set; } = [];
        public bool ReasonsApproved { get; set; }
        /// The host its file came from, which an approval shows.
        public string? SourceHost { get; set; }
    }

    internal sealed record Waiting(Tracked Download, EngineDownloadQuestion Question, EngineDownloadDestinationRequested? Held = null);

    #endregion

    #region Variables

    internal const string CanceledMessage = "Canceled.";
    internal const string DeclinedMessage = "Canceled before downloading a potentially dangerous file.";
    /// The longest host a question shows; anything longer is not a host.
    internal const int MaximumHostLength = 253;

    private readonly Dictionary<(Engine Engine, Guid ProfileId, string EngineId), Tracked> tracked = [];
    private readonly Dictionary<Guid, Tracked> byDownload = [];
    private readonly Dictionary<Guid, Waiting> waiting = [];

    /// Every engine download the ledger records.
    internal IEnumerable<Tracked> TrackedDownloads => byDownload.Values;

    /// The downloads' prompts waiting on the person.
    internal Dictionary<Guid, Waiting> WaitingPrompts => waiting;

    /// Where the identities of new records come from.
    internal IIdSource Ids => ids;

    #endregion

    #region Actions - Reports

    /// Applies what `engine` reported about one of its downloads.
    public void Report(EngineDownloadEvent report, Engine engine, EngineDownloadTurn turn) => report.Apply(this, engine, turn);

    internal void AskDestination(Tracked download, EngineDownloadDestinationRequested requested, Guid space, ChangeFeed changes) {
        waiting[requested.PromptId] = new(download, EngineDownloadQuestion.Destination);
        changes.Publish(new DownloadDestinationAsked(requested.PromptId, download.DownloadId, space,
            DownloadFilename.Safe(requested.SuggestedFilename), requested.ForcesPrompt));
    }

    /// The record of an engine download, begun on its first report in the
    /// Space it belongs to; null for one no Space can hold.
    internal Tracked? Track(Engine engine, EngineDownload reported, ChangeFeed changes, DateTimeOffset now) {
        var key = (engine, reported.ProfileId, reported.DownloadId);
        if (tracked.TryGetValue(key, out var known)) return known;
        if (SpaceOf(reported) is null) return null;
        var download = new Tracked(engine, reported.ProfileId, reported.DownloadId, ids.Next());
        tracked[key] = download;
        byDownload[download.DownloadId] = download;
        // A download the engine restored from an earlier run is already known to the person.
        Record(new BeginDownload(download.DownloadId, reported.ProfileId, DownloadFilename.Safe(reported.Filename),
            reported.StartedAt == default ? now : reported.StartedAt, reported.Restored), changes);
        // One the ledger took that began on a page of its Space leaves from that page.
        if (!reported.Restored && reported.SourcePageId is { } page && PageSpaceOf(reported) is not null
            && downloads.Ledger.IndexOf(download.DownloadId) >= 0)
            changes.Publish(new DownloadStarted(download.DownloadId, page));
        return download;
    }

    #endregion

    #region Actions - Intents

    /// Before the ledger runs a download intent: an engine download the person
    /// cancels is cancelled on its engine, one they clear leaves the engine's
    /// list, one they retry after the site's choices blocked it is replayed,
    /// and deleting a profile's data cancels and clears each of its downloads.
    public void Before(DownloadIntent intent, ChangeFeed changes, Action<Engine, EngineCommand> issue) =>
        intent.Before(this, changes, issue);

    #endregion

    #region Actions - Rules

    /// The engine download the ledger records as `downloadId`, or null.
    internal Tracked? Tracking(Guid downloadId) => byDownload.GetValueOrDefault(downloadId);

    /// Controls require a retained row in a Space the person may still use.
    internal DownloadState? Controllable(Tracked download) =>
        download.LastReport is { } report && SpaceOf(report) is not null
            ? downloads.Ledger.Items.FirstOrDefault(item => item.Id == download.DownloadId)
            : null;

    internal void SetControls(Tracked download, EngineDownload report, ChangeFeed changes) =>
        downloads.Updated(downloads.Ledger.SetControls(download.DownloadId,
            report.CanPause && !report.Paused && report.Warning is null,
            report.CanResume && report.Warning is null), changes);

    internal void Resume(Tracked download, ChangeFeed changes) {
        downloads.Updated(downloads.Ledger.Resume(download.DownloadId), changes);
        download.Estimator = null;
        download.IsLive = true;
    }

    /// The download ended: what it asked no longer waits, and later reports
    /// about it change nothing. Its identity stays, so a late report cannot
    /// bring back a record the person cleared.
    internal void End(Tracked download, ChangeFeed changes) {
        download.IsLive = false;
        download.ResumeRequested = false;
        foreach (var (id, _) in waiting.Where(entry => entry.Value.Download == download).ToArray()) Settle(id, changes);
    }

    internal void SettleApproval(Tracked download, ChangeFeed changes) {
        download.ApprovalToken = null;
        foreach (var (id, _) in waiting.Where(entry => entry.Value.Download == download && entry.Value.Question.AsksAboutEngineWarning)
                     .ToArray())
            Settle(id, changes);
    }

    /// The core's risk verdict from the platform's facts. Facts the ledger
    /// could not record ask the person first rather than passing as safe.
    internal DownloadRiskVerdict Verdict(DownloadRiskFacts facts, bool userInitiated) {
        try {
            return downloads.Answer(new DownloadRisk(facts, userInitiated));
        } catch (Rejected) {
            return new(new DownloadRiskAssessment(DownloadFilename.Safe(facts.SuggestedFilename), []), RequiresConfirmation: true);
        }
    }

    /// The downloads' prompt `promptId` names. Refused with `UnknownPrompt`
    /// when no such prompt waits.
    internal Waiting Prompt(Guid promptId) =>
        waiting.TryGetValue(promptId, out var prompt) ? prompt : throw new Rejected(new UnknownPrompt(promptId));

    internal void Settle(Guid promptId, ChangeFeed changes) {
        if (waiting.Remove(promptId)) changes.Publish(new PromptSettled(promptId));
    }

    /// The Space a download belongs to: its page's, while the page lives in a
    /// Space of the download's profile, or else the one Space of that profile
    /// the person may see.
    internal Guid? SpaceOf(EngineDownload reported) => PageSpaceOf(reported) ?? device.OnlySpaceOf(reported.ProfileId);

    /// The Space of the page a download came from, while that page lives in a
    /// Space of the download's profile the person may see; null for a download
    /// no such page started.
    private Guid? PageSpaceOf(EngineDownload reported) {
        if (reported.SourcePageId is { } pageId && pages.Hosted(pageId) is { } page && page.ProfileId == reported.ProfileId
            && device.Attached(page.WorkspaceId) is { } workspace
            && workspace.Current.Spaces.FirstOrDefault(space => space.Id == page.SpaceId) is { } pageSpace
            && !workspace.IsDeleting(pageSpace.Id) && !workspace.IsLocked(pageSpace))
            return pageSpace.Id;
        return null;
    }

    /// Runs a ledger intent the engine's report implies. One the ledger refuses,
    /// such as a reading for a record that already ended, changes nothing.
    internal void Record(DownloadIntent intent, ChangeFeed changes) {
        try {
            downloads.Handle(intent, changes);
        } catch (Rejected) {
            // The ledger keeps what it had.
        }
    }

    internal DownloadProgressReading? Sample(DownloadProgress sample) {
        try {
            return downloads.Answer(sample);
        } catch (Rejected) {
            return null;
        }
    }

    /// The file's address as the ledger names destinations.
    internal static string FileAddress(string path) => new Uri(path).AbsoluteUri;

    /// A monotonic clock in seconds, which transfer rates are measured by.
    internal static double Uptime => Stopwatch.GetTimestamp() / (double)Stopwatch.Frequency;

    /// Why a download the engine stopped failed: the warning it was blocked
    /// for, else what interrupted it.
    internal static DownloadFailure FailureOf(EngineDownload reported) =>
        reported.Warning is { } warning ? DownloadWarning.Of(warning).Failure
        : reported.Interruption is { } interruption ? EngineDownloadStop.Of(interruption).Failure
        : DownloadFailure.Interrupted;

    #endregion
}
