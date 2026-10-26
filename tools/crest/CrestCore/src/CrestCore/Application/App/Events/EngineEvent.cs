using CrestCore.Application;

namespace CrestCore.Contracts;

/// Something an engine binding saw happen to one of its pages. A report is
/// never refused: one about a page the core no longer knows changes nothing.
public abstract record EngineEvent {
    #region Abstract Methods

    /// Hands the report `engine` sent to the area it is about, which publishes
    /// what it changed to `changes`. The caller holds the app's lock.
    internal abstract void Route(CrestApp app, Engine engine, ChangeFeed changes);

    #endregion
}
