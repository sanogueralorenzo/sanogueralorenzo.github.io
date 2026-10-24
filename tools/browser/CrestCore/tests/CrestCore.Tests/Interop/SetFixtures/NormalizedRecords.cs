using CrestCore.Contracts;

namespace CrestCore.Tests.Normalized;

/// A badge lowercases its name as it is made, so two spellings of one badge
/// are equal.
[NormalizedOnConstruction]
public sealed record Badge(string Name, int Rank) : Change {
    public string Name { get; } = Name.ToLowerInvariant();
}
