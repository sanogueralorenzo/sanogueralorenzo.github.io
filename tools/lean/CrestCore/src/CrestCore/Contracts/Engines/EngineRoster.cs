namespace CrestCore.Contracts;

/// What the registered WebKit binding offers to commands and settings.
public sealed record EngineRoster(IReadOnlyList<EngineCapability> Offered) {
    public static EngineRoster Unregistered { get; } = new(EngineCapability.All);
    public bool SameAs(EngineRoster other) => Offered.SequenceEqual(other.Offered);
}
