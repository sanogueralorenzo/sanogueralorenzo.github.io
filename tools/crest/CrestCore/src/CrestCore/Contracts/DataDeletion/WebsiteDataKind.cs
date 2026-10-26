namespace CrestCore.Contracts;

/// A kind of data a site keeps in a Space's engines, as the website data list
/// names it. Engines group what they store into these kinds; a site's data is
/// always cleared whole, whatever kinds it holds. A kind travels as its index
/// in `All`, so `All` is append-only.
public sealed class WebsiteDataKind {
    #region Static Variables

    public static readonly WebsiteDataKind Cookies = new(name: "cookies", title: "Cookies");

    /// Local and session storage, IndexedDB, Cache Storage, service workers,
    /// file systems and the other storage a site's scripts write.
    public static readonly WebsiteDataKind Storage = new(name: "storage", title: "Storage");

    /// Responses the engine kept to load the site faster, which an engine
    /// that cannot list them by site does not report.
    public static readonly WebsiteDataKind Cache = new(name: "cache", title: "Cache");

    public static IReadOnlyList<WebsiteDataKind> All { get; } = [Cookies, Storage, Cache];

    #endregion

    #region Variables

    public string Name { get; }

    /// What the website data list calls the kind.
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private WebsiteDataKind(string name, string title) {
        Name = name;
        Title = title;
    }

    #endregion
}
