using CrestCore.Contracts;

namespace CrestCore.Tests.Unwatched;

/// The records of `Watched` without `[Observed]`, whose wire is the same.
public sealed record Lamp(Guid Id, string Label, bool? IsLit, IReadOnlyList<int> Levels) : Change;

public sealed record Dimmer(double Level) : Change;
