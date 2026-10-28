using System.Text.RegularExpressions;

namespace CrestCore.Contracts;

#region Types

/// One externally supplied tab. Identity, placement and lifetime belong to the core.
public sealed record LiveFolderTab(string Url, string Title);

/// A refresh arrived for another profile or a folder owned by another source.
public sealed record InvalidLiveFolder(Guid SpaceId) : Rejection;

#endregion

/// The external collection a live folder follows. Requests and credentials stay
/// in the platform's engine; only validated tab addresses reach the session.
public sealed class LiveFolderSource {
    #region Static Variables

    public static readonly LiveFolderSource GitHubPullRequests = new("githubPullRequests", "GitHub", "github.com",
        "^/[^/]+/[^/]+/pull/[1-9][0-9]*$");
    public static IReadOnlyList<LiveFolderSource> All { get; } = [GitHubPullRequests];

    #endregion

    #region Variables

    public string Name { get; }
    [Localized]
    public string Title { get; }
    private readonly string host;
    private readonly Regex path;

    #endregion

    #region Constructors

    private LiveFolderSource(string name, string title, string host, string path) {
        Name = name;
        Title = title;
        this.host = host;
        this.path = new Regex(path, RegexOptions.CultureInvariant, TimeSpan.FromSeconds(1));
    }

    #endregion

    #region Actions - Validation

    public static LiveFolderSource? Named(string? name) => All.FirstOrDefault(source => source.Name == name);

    internal bool Accepts(string? value) => value?.Length <= 4096 && Uri.TryCreate(value, UriKind.Absolute, out var url)
        && url.Scheme == Uri.UriSchemeHttps && url.Host == host && url.IsDefaultPort && url.UserInfo.Length == 0
        && url.Query.Length == 0 && url.Fragment.Length == 0 && path.IsMatch(url.AbsolutePath);

    #endregion
}
