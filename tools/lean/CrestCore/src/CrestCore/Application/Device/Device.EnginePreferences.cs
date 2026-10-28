using CrestCore.Contracts;

namespace CrestCore.Application;

/// The engine new pages use on this device. Existing pages keep their engine.
internal sealed partial class Device {
    #region Variables

    private EngineKind? defaultEngine;
    internal EngineKind? DefaultEngine => defaultEngine;
    internal EnginePreferences EnginePreferences {
        get { lock (gate) return new(defaultEngine); }
    }

    #endregion

    #region Actions - Engine settings

    internal void PreferEngine(EngineKind? engine, ChangeFeed changes) {
        lock (gate) {
            if (defaultEngine == engine) return;
            defaultEngine = engine;
            storage?.EnqueueDevice(Records());
            changes.Publish(new EnginePreferencesChanged(EnginePreferences));
        }
    }

    #endregion
}
