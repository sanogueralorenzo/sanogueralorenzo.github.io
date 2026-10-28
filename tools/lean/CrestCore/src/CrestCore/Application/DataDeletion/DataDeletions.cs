using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

/// Erases what the engines keep for a profile: all of it, some sites', or what
/// changed in a time range. Every registered engine is asked, whether or not
/// it has started or shows any page, since a profile's store outlives the run
/// that filled it. A deletion ends with `DataDeleted` once each engine asked
/// has answered, deleted only when every one of them erased everything. A
/// profile whose data this run erased may finish its Space's deletion; a
/// relaunch erases it again before that deletion finishes. Nothing here is
/// saved.
internal sealed class DataDeletions(Engines engines, IIdSource ids, IClock clock) {
    #region Static Variables

    /// The longest host a site can have.
    internal const int MaximumHostLength = 253;

    #endregion

    #region Types

    /// One deletion, until every engine asked has answered.
    internal sealed class Deletion(Guid requestId, Guid? profileId) {
        public Guid RequestId { get; } = requestId;
        /// The profile whose data this erases in full, if it does.
        public Guid? ProfileId { get; } = profileId;
        /// The erasures still out, each with the engine it went to.
        public Dictionary<Guid, Engine> Waiting { get; } = [];
        public bool Erased { get; set; } = true;
    }

    #endregion

    #region Variables

    private readonly Dictionary<Guid, Deletion> byErasure = [];
    /// The profiles whose data this run erased in full.
    private readonly HashSet<Guid> erasedProfiles = [];

    /// Each erasure an engine has yet to answer, with its deletion.
    internal Dictionary<Guid, Deletion> ByErasure => byErasure;

    /// The profiles whose data this run erased in full.
    internal HashSet<Guid> ErasedProfiles => erasedProfiles;

    /// The time a deletion's range ends at.
    internal IClock Clock => clock;

    #endregion

    #region Actions - Intents

    /// Runs one data deletion intent, handing each engine its part.
    public void Handle(DataDeletionIntent intent, ChangeFeed changes, Action<Engine, EngineCommand> issue) => intent.Apply(this, changes, issue);

    /// Asks every registered engine for its part of `deletion`.
    internal void Start(Deletion deletion, Func<Guid, EngineCommand> erasing, ChangeFeed changes,
        Action<Engine, EngineCommand> issue) {
        foreach (var engine in engines.All) {
            var erasure = ids.Next();
            deletion.Waiting[erasure] = engine;
            byErasure[erasure] = deletion;
            issue(engine, erasing(erasure));
        }
        if (deletion.Waiting.Count == 0) Finish(deletion, changes);
    }

    #endregion

    #region Actions - Reports

    internal void Finish(Deletion deletion, ChangeFeed changes) {
        if (deletion.Erased && deletion.ProfileId is { } profile) erasedProfiles.Add(profile);
        changes.Publish(new DataDeleted(deletion.RequestId, deletion.Erased));
    }

    #endregion

    #region Actions - Queries

    /// Whether this run erased profile `profileId`'s data on every engine.
    public bool Erased(Guid profileId) => erasedProfiles.Contains(profileId);

    /// Whether the engines are erasing profile `profileId`'s data now, which
    /// a quit would interrupt. A Space deletion that is not erasing waits for
    /// nothing: it finishes, or a later attempt or launch erases it again.
    public bool Erasing(Guid profileId) => byErasure.Values.Any(deletion => deletion.ProfileId == profileId);

    #endregion
}
