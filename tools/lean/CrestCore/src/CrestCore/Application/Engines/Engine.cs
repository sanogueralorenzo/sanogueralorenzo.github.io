using CrestCore.Contracts;

namespace CrestCore.Application;

/// One registered engine binding: which engine it is, whether new pages open
/// on it, and how the core hands it a command. A retired engine takes no more
/// commands, including ones issued before it was retired.
public sealed class Engine {
    #region Variables

    public EngineKind Kind { get; }

    /// New pages open on this engine.
    public bool IsDefault { get; }

    /// What the binding said it supports when it registered.
    private readonly IReadOnlyList<EngineCapability> capabilities;
    private readonly Action<EngineCommand> run;
    private volatile bool isRetired;

    #endregion

    #region Constructors

    internal Engine(EngineRegistration registration, Action<EngineCommand> run) {
        Kind = registration.Kind;
        IsDefault = registration.IsDefault;
        capabilities = [.. registration.Capabilities];
        this.run = run;
    }

    #endregion

    #region Actions - Capabilities

    /// Whether the binding supports `capability`.
    internal bool Supports(EngineCapability capability) => capabilities.Contains(capability);

    /// The engine as the read model shows it.
    internal EngineState State(bool isDefault) => new(Kind, [.. EngineCapability.All.Where(Supports)], isDefault);

    #endregion

    #region Actions - Commands

    /// Hands the binding one command, unless the engine has been retired.
    internal void Run(EngineCommand command) {
        if (!isRetired) run(command);
    }

    /// Stops every later command from reaching the binding.
    internal void Retire() => isRetired = true;

    #endregion
}
