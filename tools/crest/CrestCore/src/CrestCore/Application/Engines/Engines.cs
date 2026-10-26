using CrestCore.Contracts;

namespace CrestCore.Application;

/// The engine bindings this core hosts pages on, by kind. One of them is the
/// default, which new pages open on. Never saved or synced: a composition
/// registers what it carries every time it starts.
internal sealed class Engines {
    #region Variables

    private readonly Dictionary<EngineKind, Engine> registered = [];
    private EngineKind? preferred;

    /// Every registered engine, whether or not it has started.
    public IReadOnlyCollection<Engine> All => registered.Values;

    /// The engine new pages open on, or null while none is registered.
    public Engine? Default => preferred is { } kind && registered.TryGetValue(kind, out var chosen)
        ? chosen : registered.Values.FirstOrDefault(engine => engine.IsDefault);

    #endregion

    #region Actions - Queries

    /// Every registered engine, as the read model shows them, and what the
    /// device offers where `hosting` names the engines a page is open on: what
    /// the default engine supports, what each engine that hosts a page
    /// supports, and, of the capabilities that start their engine on demand,
    /// what any registered engine supports.
    public EngineRoster Roster(IReadOnlySet<EngineKind> hosting) {
        if (registered.Count == 0) return EngineRoster.Unregistered;
        var defaultEngine = Default;
        var offering = registered.Values.Where(engine => ReferenceEquals(engine, defaultEngine) || hosting.Contains(engine.Kind)).ToArray();
        return new([.. EngineKind.All.Where(registered.ContainsKey).Select(kind => registered[kind].State(ReferenceEquals(registered[kind], defaultEngine)))],
            [.. EngineCapability.All.Where(capability => offering.Any(engine => engine.Supports(capability))
                || capability.StartsEngineOnDemand && registered.Values.Any(engine => engine.Supports(capability)))]);
    }

    /// The commands `roster` offers, in catalog order: those whose whole
    /// feature it offers. A page's own engine decides whether the command can
    /// act on it.
    public static IReadOnlyList<ShortcutCommand> OfferedCommands(EngineRoster roster) {
        var offered = roster.Offered;
        return [.. ShortcutCommand.All.Where(command => command.IsOffered(offered.Contains))];
    }

    /// The registered engine of `kind`, or null while none is.
    public Engine? Registered(EngineKind kind) => registered.GetValueOrDefault(kind);

    /// The first registered engine, in `EngineKind.All` order, other than
    /// `except`, that plays protected media through the platform, or null
    /// when none does.
    public Engine? PlayingProtectedMedia(Engine except) => EngineKind.All.Select(registered.GetValueOrDefault)
        .FirstOrDefault(engine => engine is not null && !ReferenceEquals(engine, except) && engine.Supports(EngineCapability.ProtectedMedia));

    #endregion

    #region Actions - Registration

    /// Uses the person's device choice where it is available, otherwise the
    /// composition's default. Choosing an engine starts no runtime or page.
    internal void Prefer(EngineKind? kind) => preferred = kind;

    /// Registers a binding that supports every required capability, as the
    /// default only when no other engine is. Throws `Rejected` naming the rule
    /// it breaks.
    public Engine Register(EngineRegistration registration, Action<EngineCommand> run) {
        ArgumentNullException.ThrowIfNull(registration);
        ArgumentNullException.ThrowIfNull(run);
        if (EngineCapability.Required.FirstOrDefault(capability => !registration.Capabilities.Contains(capability)) is { } missing)
            throw new Rejected(new EngineLacksCapability(registration.Kind, missing));
        if (registered.ContainsKey(registration.Kind)) throw new Rejected(new EngineAlreadyRegistered(registration.Kind));
        if (registration.IsDefault && registered.Values.FirstOrDefault(engine => engine.IsDefault) is { } existing)
            throw new Rejected(new DefaultEngineAlreadyRegistered(existing.Kind));
        var engine = new Engine(registration, run);
        registered[engine.Kind] = engine;
        return engine;
    }

    /// Removes a binding, which takes no more commands. Its pages stay until
    /// their owners release them.
    public void Unregister(Engine engine) {
        ArgumentNullException.ThrowIfNull(engine);
        if (registered.TryGetValue(engine.Kind, out var current) && ReferenceEquals(current, engine)) registered.Remove(engine.Kind);
        engine.Retire();
    }

    /// Retires every binding: the core is going away.
    public void Clear() {
        foreach (var engine in registered.Values) engine.Retire();
        registered.Clear();
    }

    #endregion
}
