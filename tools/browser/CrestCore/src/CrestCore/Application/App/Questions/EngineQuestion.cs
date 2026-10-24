using CrestCore.Application;

namespace CrestCore.Contracts;

/// What an engine binding asks the core about one of its pages while the
/// engine waits, such as what a person's click on a link does. The core
/// answers with a `TAnswer` at once, from its state, and changes nothing.
public abstract record EngineQuestion<TAnswer> {
    #region Abstract Methods

    /// The answer to what `engine` asks, from what `app` holds, changing
    /// nothing. The caller holds the app's lock.
    internal abstract TAnswer Answer(CrestApp app, Engine engine);

    #endregion
}
