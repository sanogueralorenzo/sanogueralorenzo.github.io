namespace CrestCore.Contracts;

#region Queries

/// For each candidate, in order, whether it names the asked language.
public sealed record LanguageMatches(IReadOnlyList<bool> Matches);

/// How one launch treats the person's data and what its first window opens.
/// An isolated launch never reads or writes the installed profile.
/// `UsesEphemeralProfileStorage` keeps page and extension web storage in the
/// same privacy class: both forget, unless a named isolated profile persists
/// both. `PresentsInstalledApplicationUI` is false only under the test runtime.
public sealed record LaunchDecision(bool RequiresIsolation, bool UsesEphemeralProfileStorage, bool PresentsInstalledApplicationUI);

#endregion

#region Rejections

/// Only the persistent workspace keeps the app-wide preferences and takes
/// imported Spaces.
public sealed record PersistentWorkspaceRequired(Guid WorkspaceId) : Rejection {
    #region Variables

    /// What the person is told.
    [Localized]
    public string Message => "Open a regular window to do this.";

    #endregion
}

#endregion
