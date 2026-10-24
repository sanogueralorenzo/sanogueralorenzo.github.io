using CrestCore.Contracts;

namespace CrestCore.Tests.Unnormalizable;

/// Nothing to normalize, and no field for the wire initializer's label.
[NormalizedOnConstruction]
public sealed record Blank() : Change;

/// Swift compares an option set but cannot hash it.
[NormalizedOnConstruction]
public sealed record Tinted(Hues Hues) : Change;

[Flags]
public enum Hues {
    None = 0,
    Red = 1,
    Blue = 2
}
