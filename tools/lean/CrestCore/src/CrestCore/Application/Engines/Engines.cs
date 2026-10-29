using CrestCore.Contracts;

namespace CrestCore.Application;

/// The one WebKit binding this app hosts pages on.
internal sealed class Engines {
    public Engine? Default { get; private set; }
    public IReadOnlyCollection<Engine> All => Default is { } engine ? [engine] : [];

    public EngineRoster Roster() => Default is { } engine
        ? new([.. EngineCapability.All.Where(engine.Supports)]) : EngineRoster.Unregistered;

    public static IReadOnlyList<ShortcutCommand> OfferedCommands(EngineRoster roster) =>
        [.. ShortcutCommand.All.Where(command => command.IsOffered(roster.Offered.Contains))];

    public Engine Register(EngineRegistration registration, Action<EngineCommand> run) {
        ArgumentNullException.ThrowIfNull(registration);
        ArgumentNullException.ThrowIfNull(run);
        if (Default is not null) throw new Rejected(new EngineAlreadyRegistered());
        if (EngineCapability.Required.FirstOrDefault(capability => !registration.Capabilities.Contains(capability)) is { } missing)
            throw new Rejected(new EngineLacksCapability(missing));
        return Default = new Engine(registration, run);
    }

    public void Unregister(Engine engine) {
        ArgumentNullException.ThrowIfNull(engine);
        if (ReferenceEquals(Default, engine)) Default = null;
        engine.Retire();
    }

    public void Clear() {
        Default?.Retire();
        Default = null;
    }
}
