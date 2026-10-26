namespace CrestCore.Contracts;

/// <summary>
/// What a person chose for a Space apart from its records: its name, look and
/// preferences.
/// </summary>
[Observed]
public sealed record SpaceSettings(
    string Name,
    BrowsingPreferences BrowsingPreferences,
    bool IsGitHubFolderDismissed = false,
    SpaceColor? StoredColor = null) {
    #region Variables

    [Resolved]
    public SpaceColor Color => StoredColor ?? SpaceColor.Blue;

    #endregion
}
