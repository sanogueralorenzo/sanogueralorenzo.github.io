using CrestCore.Contracts;

namespace CrestCore.Application;

/// Which engine each site's new pages open on. The device store keeps the
/// choices made in the persistent session's Spaces, which hold for every
/// Space; a choice made in any other Space (private, seeded, or one no
/// attached session holds) holds for that Space alone and lives in memory
/// until the process ends. Such a Space still follows the kept choices.
internal sealed partial class Device {
    #region Variables

    /// The persistent session's choices, which the device store keeps.
    private readonly SiteEngineLedger keptEngines = new();
    /// Every other Space's choices, which live as long as the process.
    private readonly SiteEngineLedger passingEngines = new();
    private EngineKind? defaultEngine;

    /// The person's default choice, separate from what this composition carries.
    internal EngineKind? DefaultEngine => defaultEngine;

    /// Persistent engine choices only. Private choices never enter Settings.
    internal EnginePreferences EnginePreferences {
        get {
            lock (gate) return new(defaultEngine, [.. keptEngines.Choices.Select(choice => new SiteEngineRule(choice.Origin, choice.Engine))]);
        }
    }

    #endregion

    #region Actions - Site engine intents

    /// Opens `origin`'s new pages on `engine` from now on, as a choice made in
    /// `spaceId`: for every Space when the device store keeps its choices, or
    /// for that Space alone. Throws `Rejected` for an origin that is not valid
    /// or a locked Space.
    public void Choose(Guid spaceId, SiteOrigin origin, EngineKind engine) {
        ArgumentNullException.ThrowIfNull(origin);
        ArgumentNullException.ThrowIfNull(engine);
        if (!origin.IsValid) throw new Rejected(new InvalidSiteOrigin(origin));
        var (keeps, locked) = ChoiceScope(spaceId);
        if (locked) throw new Rejected(new SpaceLocked(spaceId));
        lock (gate) {
            if (keeps) {
                if (keptEngines.Choose(new(null, origin, engine))) {
                    storage?.EnqueueDevice(Records());
                    announce(new EnginePreferencesChanged(EnginePreferences));
                }
            } else {
                passingEngines.Choose(new(spaceId, origin, engine));
            }
        }
    }

    #endregion

    #region Actions - Engine settings

    /// Chooses the default for future pages, without moving existing pages.
    internal void PreferEngine(EngineKind? engine, ChangeFeed changes) {
        lock (gate) {
            if (defaultEngine == engine) return;
            defaultEngine = engine;
            KeepEnginePreferences(changes);
        }
    }

    /// Adds or edits an ordinary website rule. An edit can change its origin
    /// atomically; a private page's menu continues to use its passing ledger.
    internal void EditEngineRule(SiteOrigin? previous, SiteOrigin origin, EngineKind engine, ChangeFeed changes) {
        if (!origin.IsValid) throw new Rejected(new InvalidSiteOrigin(origin));
        if (previous is not null && !previous.IsValid) throw new Rejected(new InvalidSiteOrigin(previous));
        lock (gate) {
            bool changed = previous is not null && previous != origin && keptEngines.Forget(null, previous);
            changed |= keptEngines.Choose(new(null, origin, engine));
            if (changed) KeepEnginePreferences(changes);
        }
    }

    /// Returns a website to the default engine.
    internal void ForgetEngineRule(SiteOrigin origin, ChangeFeed changes) {
        if (!origin.IsValid) throw new Rejected(new InvalidSiteOrigin(origin));
        lock (gate) {
            if (keptEngines.Forget(null, origin)) KeepEnginePreferences(changes);
        }
    }

    private void KeepEnginePreferences(ChangeFeed changes) {
        storage?.EnqueueDevice(Records());
        changes.Publish(new EnginePreferencesChanged(EnginePreferences));
    }

    #endregion

    #region Actions - Site engine queries

    /// The engine chosen for new pages of `origin` in `spaceId`, or null when
    /// none is. Called without the device lock, since it reads the sessions.
    public EngineKind? ChosenEngine(Guid spaceId, SiteOrigin origin) {
        ArgumentNullException.ThrowIfNull(origin);
        var (keeps, _) = ChoiceScope(spaceId);
        lock (gate) return (keeps ? null : passingEngines.Chosen(spaceId, origin)) ?? keptEngines.Chosen(null, origin);
    }

    #endregion
}
