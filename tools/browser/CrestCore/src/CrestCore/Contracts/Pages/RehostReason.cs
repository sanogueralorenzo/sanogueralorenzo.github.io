namespace CrestCore.Contracts;

/// Why a page moved to another engine. A reason travels as its index in
/// `All`, so `All` is append-only.
public sealed class RehostReason {
    #region Variables

    /// The person chose another engine for the page (`RehostPage`).
    public static readonly RehostReason PersonAsked = new(name: "personAsked");

    /// The page headed to a site chosen for another engine.
    public static readonly RehostReason SiteChoice = new(name: "siteChoice");

    /// The page asked for protected media its engine cannot play, and another
    /// engine plays it through the platform. The page's site opens there from
    /// then on, and the person may move it back.
    public static readonly RehostReason ProtectedMedia = new(name: "protectedMedia");

    public static IReadOnlyList<RehostReason> All { get; } = [PersonAsked, SiteChoice, ProtectedMedia];

    public string Name { get; }

    #endregion

    #region Constructors

    private RehostReason(string name) => Name = name;

    #endregion

    #region Actions - Lookup

    public static RehostReason? Named(string? name) => All.FirstOrDefault(reason => reason.Name == name);

    #endregion
}
