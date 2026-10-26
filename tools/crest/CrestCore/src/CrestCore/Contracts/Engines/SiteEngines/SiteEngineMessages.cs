namespace CrestCore.Contracts;

#region Models

/// A website explicitly assigned to an engine on this device.
public sealed record SiteEngineRule(SiteOrigin Origin, EngineKind Engine);

#endregion

#region Changes

/// The device's ordinary engine preferences changed. Private choices are absent.
public sealed record EnginePreferencesChanged(EnginePreferences Preferences) : Change;

#endregion

#region Rejections

/// This device registered no engine of `Kind`, so no page can open on it.
public sealed record UnregisteredEngine(EngineKind Kind) : Rejection;

#endregion
