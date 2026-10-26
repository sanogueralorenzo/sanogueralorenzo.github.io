namespace CrestCore.Contracts;

#region Changes

/// The device's global engine preference changed.
public sealed record EnginePreferencesChanged(EnginePreferences Preferences) : Change;

#endregion

#region Rejections

/// This device registered no engine of `Kind`, so no page can open on it.
public sealed record UnregisteredEngine(EngineKind Kind) : Rejection;

#endregion
