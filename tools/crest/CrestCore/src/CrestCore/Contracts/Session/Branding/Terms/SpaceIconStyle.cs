namespace CrestCore.Contracts;

/// Whether a Space's icon is a plain symbol or its layered crest.
public sealed class SpaceIconStyle {
    #region Types

    /// Each style is drawn by a different view, so the code that draws an icon switches over the kind.
    public enum Kinds { SimpleSymbol, LayeredCrest }

    #endregion

    #region Variables

    public static readonly SpaceIconStyle SimpleSymbol = new(Kinds.SimpleSymbol, "simpleSymbol", "Icon");
    public static readonly SpaceIconStyle LayeredCrest = new(Kinds.LayeredCrest, "layeredCrest", "Crest");

    public static IReadOnlyList<SpaceIconStyle> All { get; } = [SimpleSymbol, LayeredCrest];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The choice's name where a person picks it.
    [Localized]
    public string Title { get; }

    #endregion

    #region Constructors

    private SpaceIconStyle(Kinds kind, string name, string title) {
        Kind = kind;
        Name = name;
        Title = title;
    }

    #endregion

    #region Actions - Lookup

    public static SpaceIconStyle? Named(string? name) => All.FirstOrDefault(style => style.Name == name);

    #endregion
}
