namespace CrestCore.Contracts;

/// <summary>
/// What a person chose for a Space apart from its records: its name, look and
/// preferences, who may open it, and whether its saved tabs are expanded.
/// <see cref="CredentialsEnabledModifiedAt"/> is when the person last turned
/// Crest Passwords on or off for the Space, on any device, or null when nobody has.
/// <see cref="AccessPolicyModifiedAt"/> is when the person last turned the Space's lock
/// on or off, on any device, or null when nobody has since Crest kept that time.
/// <see cref="Branding"/> is null for a Space stored before branding existed, which
/// wears the look its accent and symbol give it; <see cref="Look"/> is what it wears.
/// </summary>
[Observed]
public sealed record SpaceSettings(
    string Name,
    string Symbol,
    SpaceAccent Accent,
    SpaceBranding? Branding,
    BrowsingPreferences BrowsingPreferences,
    CredentialPreferences CredentialPreferences,
    SpaceAccessPolicy AccessPolicy,
    bool IsSavedTabsExpanded,
    DateTimeOffset? SavedTabsExpansionModifiedAt,
    DateTimeOffset? CredentialsEnabledModifiedAt = null,
    DateTimeOffset? AccessPolicyModifiedAt = null) {
    #region Variables

    /// <summary>The branding the Space wears: its own, with a banner strength stored
    /// before the baseline vocabulary in today's units, or for a Space stored before
    /// branding existed, the legacy look of its accent and symbol.</summary>
    [Resolved]
    public SpaceBranding Look => Branding?.InTodaysUnits() ?? SpaceBranding.Legacy(Accent, Symbol);

    /// <summary>The Space shows only while this process holds the grant for its
    /// profile. A policy this build cannot name reads as guarded (see
    /// `StoredSessionCodec`), so only an open Space skips authentication.</summary>
    [Resolved]
    public bool RequiresAuthentication => AccessPolicy != SpaceAccessPolicy.Open;

    #endregion
}
