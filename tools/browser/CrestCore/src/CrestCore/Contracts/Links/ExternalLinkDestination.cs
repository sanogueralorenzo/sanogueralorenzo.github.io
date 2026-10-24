namespace CrestCore.Contracts;

/// Where a link opened from outside Crest goes when no route claims it: the
/// Space it opens in, and whether it opens as a Quick Window there.
///
/// Link preferences (`crest.link-preferences.v1`) spell a destination as its
/// `Name`, so a name never changes. A destination travels as its index in
/// `All`, so `All` is append-only.
public sealed class ExternalLinkDestination {
    #region Variables

    /// A Quick Window on the Space remembered for the link's site, when the
    /// preferences remember one and it can open.
    public static readonly ExternalLinkDestination QuickWindow = new(name: "quickWindow", title: "Quick Window",
        opensQuickWindow: true, space: (preferences, remembered, context) =>
            preferences.RemembersSpaceBySite && remembered is { } site && context.IsAvailable(site) ? site : context.Fallback());

    public static readonly ExternalLinkDestination MostRecentSpace = new(name: "mostRecentSpace", title: "Most Recent Space",
        opensQuickWindow: false, space: (_, _, context) => context.Fallback());

    /// The Space the person chose, when it can open.
    public static readonly ExternalLinkDestination ChosenSpace = new(name: "chosenSpace", title: "Chosen Space",
        opensQuickWindow: false, asksForSpace: true, space: (preferences, _, context) =>
            preferences.DestinationSpaceId is { } chosen && context.IsAvailable(chosen) ? chosen : context.Fallback());

    public static IReadOnlyList<ExternalLinkDestination> All { get; } = [QuickWindow, MostRecentSpace, ChosenSpace];

    public string Name { get; }

    /// What the link settings call the destination.
    [Localized]
    public string Title { get; }

    public bool OpensQuickWindow { get; }

    /// The link settings ask which Space the destination opens.
    public bool AsksForSpace { get; }

    private readonly Func<LinkPreferences, Guid?, LinkRoutingContext, Guid> space;

    #endregion

    #region Constructors

    private ExternalLinkDestination(string name, string title, bool opensQuickWindow,
        Func<LinkPreferences, Guid?, LinkRoutingContext, Guid> space, bool asksForSpace = false) {
        Name = name;
        Title = title;
        OpensQuickWindow = opensQuickWindow;
        AsksForSpace = asksForSpace;
        this.space = space;
    }

    #endregion

    #region Actions - Lookup

    public static ExternalLinkDestination? Named(string? name) => All.FirstOrDefault(destination => destination.Name == name);

    #endregion

    #region Actions - Routing

    /// The Space a link with no matching route opens in, with `remembered`,
    /// the Space the preferences remember for the link's site, if any. The
    /// selected Space, or the first that can open, stands in for one that
    /// cannot.
    public Guid Space(LinkPreferences preferences, Guid? remembered, LinkRoutingContext context) {
        ArgumentNullException.ThrowIfNull(preferences);
        ArgumentNullException.ThrowIfNull(context);
        return space(preferences, remembered, context);
    }

    #endregion
}
