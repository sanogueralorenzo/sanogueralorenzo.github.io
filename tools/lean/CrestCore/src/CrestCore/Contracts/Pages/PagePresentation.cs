namespace CrestCore.Contracts;

/// What a page surface shows for a tab: nothing selected, the Start Page, a
/// native view, the live page, the page's failed navigation, its engine's
/// failed process, or, without a page, the tab waiting unloaded or restoring
/// itself. A presentation travels as its index in `All`, so `All` is
/// append-only.
public sealed class PagePresentation {
    #region Static Variables

    public static readonly PagePresentation NoSelection = new(name: "noSelection");
    public static readonly PagePresentation StartPage = new(name: "startPage");
    public static readonly PagePresentation NativeContent = new(name: "nativeContent");
    public static readonly PagePresentation LivePage = new(name: "livePage");
    public static readonly PagePresentation NavigationFailure = new(name: "navigationFailure");
    public static readonly PagePresentation ProcessFailure = new(name: "processFailure");
    public static readonly PagePresentation Unloaded = new(name: "unloaded");
    public static readonly PagePresentation AutomaticRestore = new(name: "automaticRestore");

    public static IReadOnlyList<PagePresentation> All { get; } =
        [NoSelection, StartPage, NativeContent, LivePage, NavigationFailure, ProcessFailure, Unloaded, AutomaticRestore];

    #endregion

    #region Variables

    public string Name { get; }

    #endregion

    #region Constructors

    private PagePresentation(string name) => Name = name;

    #endregion

    #region Actions - Lookup

    public static PagePresentation? Named(string? name) => All.FirstOrDefault(presentation => presentation.Name == name);

    /// What a surface shows for a tab whose surface is `surface`, or none: a
    /// Start Page or native view as it is, and a web page as its page stands,
    /// a navigation failure outranking a process failure; without a page, the
    /// tab restores itself where the surface asks, else waits unloaded.
    public static PagePresentation Of(PresentPage question) {
        ArgumentNullException.ThrowIfNull(question);
        if (question.Surface is not { } surface) return NoSelection;
        if (surface == TabSurface.StartPage) return StartPage;
        if (!surface.ShowsPage) return NativeContent;
        if (!question.HasPage) return question.RestoresUnloaded ? AutomaticRestore : Unloaded;
        return question.HasNavigationFailure ? NavigationFailure : question.HasProcessFailure ? ProcessFailure : LivePage;
    }

    #endregion
}
