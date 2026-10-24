using CrestCore.Contracts;

namespace CrestCore.Tests.Unwatchable;

/// The model reads its record back as `value`, which this field would hide.
[Observed]
public sealed record Valued(Guid Id, string Value) : Change;

/// A model's identity is a GUID.
[Observed]
public sealed record Numbered(int Id) : Change;

/// No contract message carries it, so no model would ever be updated.
[Observed]
public sealed record Unreached(Guid Id);
