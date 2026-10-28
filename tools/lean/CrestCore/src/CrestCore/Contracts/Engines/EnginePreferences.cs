namespace CrestCore.Contracts;

/// The device's global engine choice; null follows the composition's default.
public sealed record EnginePreferences(EngineKind? DefaultEngine);
