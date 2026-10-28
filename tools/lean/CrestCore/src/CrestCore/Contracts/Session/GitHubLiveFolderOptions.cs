using System.Text.RegularExpressions;

namespace CrestCore.Contracts;

/// User choices for one GitHub live folder. New folders include created and assigned PRs.
public sealed record GitHubLiveFolderOptions(bool AuthorMe, bool AssignedMe, bool ReviewRequested, bool IncludeDrafts,
    IReadOnlyList<string> ExcludedRepositories, LiveFolderRefreshInterval Interval) {
    #region Static Variables

    public static GitHubLiveFolderOptions Default { get; } = new(true, true, false, true, [], LiveFolderRefreshInterval.ThirtyMinutes);
    private static readonly Regex Repository = new("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", RegexOptions.CultureInvariant,
        TimeSpan.FromSeconds(1));

    #endregion

    #region Variables

    internal bool IsValid => ExcludedRepositories.Count <= 100
        && ExcludedRepositories.All(repository => repository.Length <= 256 && Repository.IsMatch(repository.Trim()));

    #endregion

    #region Actions - Editing

    internal GitHubLiveFolderOptions Normalized() => this with {
        ExcludedRepositories = ExcludedRepositories.Select(repository => repository.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase).Order(StringComparer.OrdinalIgnoreCase).ToArray()
    };

    internal bool Matches(GitHubLiveFolderOptions other) => AuthorMe == other.AuthorMe && AssignedMe == other.AssignedMe
        && ReviewRequested == other.ReviewRequested && IncludeDrafts == other.IncludeDrafts && Interval == other.Interval
        && ExcludedRepositories.SequenceEqual(other.ExcludedRepositories, StringComparer.OrdinalIgnoreCase);

    #endregion
}
