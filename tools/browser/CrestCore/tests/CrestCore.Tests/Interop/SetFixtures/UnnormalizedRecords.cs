using CrestCore.Contracts;

namespace CrestCore.Tests.Unnormalized;

/// The badge of `Normalized` without `[NormalizedOnConstruction]`, whose wire is the same.
public sealed record Badge(string Name, int Rank) : Change {
    public string Name { get; } = Name.ToLowerInvariant();
}
