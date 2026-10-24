namespace CrestCore.Contracts;

/// What a tab's surface shows: the Start Page, a native view, or a web page,
/// which only a page on the tab's engine can show. A surface travels as its
/// index in `All`, so `All` is append-only.
public sealed class TabSurface {
    #region Static Variables

    public static readonly TabSurface StartPage = new(name: "startPage", showsPage: false);
    public static readonly TabSurface NativeView = new(name: "nativeView", showsPage: false);
    public static readonly TabSurface WebPage = new(name: "webPage", showsPage: true);

    public static IReadOnlyList<TabSurface> All { get; } = [StartPage, NativeView, WebPage];

    #endregion

    #region Variables

    public string Name { get; }

    /// The surface shows a web page, which needs a page on the tab's engine;
    /// without one the tab waits unloaded.
    public bool ShowsPage { get; }

    #endregion

    #region Constructors

    private TabSurface(string name, bool showsPage) {
        Name = name;
        ShowsPage = showsPage;
    }

    #endregion

    #region Actions - Lookup

    public static TabSurface? Named(string? name) => All.FirstOrDefault(surface => surface.Name == name);

    /// The surface of a tab that shows `nativeView` or `address`, or neither.
    public static TabSurface Of(NativeTabContent? nativeView, string? address) =>
        nativeView is not null ? NativeView : address is null ? StartPage : WebPage;

    #endregion
}
