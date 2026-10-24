namespace CrestCore.Contracts;

/// Every engine this device registered, in `EngineKind.All` order, and what
/// the device offers anywhere a person can find a feature, such as a menu,
/// the launcher or a settings page, in `EngineCapability.All` order: what the
/// default engine supports, and what each engine a page is open on supports,
/// so an engine no page uses offers nothing the person could not use. Every
/// capability is offered until an engine registers. Whether a page can use
/// one is its own engine's answer.
public sealed record EngineRoster(IReadOnlyList<EngineState> Engines, IReadOnlyList<EngineCapability> Offered) {
    #region Static Variables

    /// The roster before any engine registers.
    public static EngineRoster Unregistered { get; } = new([], EngineCapability.All);

    #endregion

    #region Variables

    /// The engines whose pages wear a badge on their tab's icon, so the person
    /// can tell which engine hosts a page: every engine but the default, once
    /// the device registered more than one. A device with one engine badges
    /// none, since every page runs on it.
    [Resolved]
    public IReadOnlyList<EngineKind> Badged => Engines.Count > 1
        ? [.. Engines.Where(engine => !engine.IsDefault).Select(engine => engine.Kind)]
        : [];

    #endregion

    #region Actions - Comparison

    /// Whether both rosters hold the same engines and offer the same
    /// capabilities.
    public bool SameAs(EngineRoster other) => Offered.SequenceEqual(other.Offered) && Engines.Count == other.Engines.Count
        && Engines.Zip(other.Engines).All(pair => pair.First.Kind == pair.Second.Kind && pair.First.IsDefault == pair.Second.IsDefault
            && pair.First.Capabilities.SequenceEqual(pair.Second.Capabilities));

    #endregion
}
