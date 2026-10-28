namespace CrestCore.Contracts;

#region Queries

/// For each candidate, in order, whether it names the asked language.
public sealed record LanguageMatches(IReadOnlyList<bool> Matches);

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
