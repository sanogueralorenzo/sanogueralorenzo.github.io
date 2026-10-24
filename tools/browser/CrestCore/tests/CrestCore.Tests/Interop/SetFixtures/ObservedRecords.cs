using CrestCore.Contracts;

namespace CrestCore.Tests.Watched;

// A contract record another record holds lives in the contracts assembly, so
// these fixtures are observed as the changes that carry them.

/// A record views observe field by field, whose model keeps `Id` as its identity.
[Observed]
public sealed record Lamp(Guid Id, string Label, bool? IsLit, IReadOnlyList<int> Levels) : Change;

/// An observed record without an identity of its own.
[Observed]
public sealed record Dimmer(double Level) : Change;
