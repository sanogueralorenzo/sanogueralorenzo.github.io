namespace CrestCore.Contracts;

#region Types

/// A mark Crest draws for an engine, beside its name and on the badge a tab's
/// icon wears while its page runs on it. Each is Crest's own artwork, never the
/// engine's logo, which is its owner's trademark; each platform draws it once.
public enum EngineMark {
    /// A blue tile stacked on a warm one, seen from above at an angle.
    StackedTile,
    /// A blue globe for an engine using Chromium.
    Globe,
}

#endregion

/// A browsing engine Crest can host pages on. A composition registers the
/// engines it carries, one of them as the default, and each page belongs to
/// one engine. A kind travels as its index in `All`, so `All` is append-only.
public sealed class EngineKind {
    #region Static Variables

    public static readonly EngineKind Chromium = new(name: "chromium", title: "Chromium", mark: EngineMark.Globe,
        pageDescription: "Runs in Chromium");
    public static readonly EngineKind WebKit = new(name: "webkit", title: "WebKit", mark: EngineMark.StackedTile,
        pageDescription: "Runs in WebKit");

    public static IReadOnlyList<EngineKind> All { get; } = [Chromium, WebKit];

    #endregion

    #region Variables

    public string Name { get; }

    /// The engine's name as the person reads it, where Crest says which
    /// engine hosts a page.
    [Localized]
    public string Title { get; }

    public string TitleComment { get; } = "The name of a browser engine. Keep the product name as it is.";

    /// The mark that stands for the engine beside its name and on the badge a
    /// tab's icon wears while its page runs on it. The roster badges pages
    /// that use an engine other than the person's default.
    public EngineMark? Mark { get; }

    /// What a tab says about the engine its page runs on to someone who
    /// cannot see its badge, and what the badge says on hover.
    [Localized]
    public string PageDescription { get; }

    public string PageDescriptionComment { get; } =
        "Said of a tab whose page runs in this browser engine rather than the default one. Keep the product name as it is.";

    #endregion

    #region Constructors

    private EngineKind(string name, string title, EngineMark? mark, string pageDescription) {
        Name = name;
        Title = title;
        Mark = mark;
        PageDescription = pageDescription;
    }

    #endregion

    #region Actions - Lookup

    public static EngineKind? Named(string? name) => All.FirstOrDefault(kind => kind.Name == name);

    #endregion
}
