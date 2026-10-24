namespace CrestCore.Contracts;

/// The letterforms of a monogram charge.
public sealed class CrestMonogramStyle {
    #region Types

    /// Each platform chooses each style's typeface, so its renderer switches over the kind.
    public enum Kinds { Serif, Sans }

    #endregion

    #region Variables

    public static readonly CrestMonogramStyle Serif = new(Kinds.Serif, "serif", "Serif", CrestVocabulary.Studio);
    public static readonly CrestMonogramStyle Sans = new(Kinds.Sans, "sans", "Sans", CrestVocabulary.Studio);

    public static IReadOnlyList<CrestMonogramStyle> All { get; } = [Serif, Sans];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The term's name in the Studio.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws it.
    public CrestVocabulary DrawnSince { get; }

    #endregion

    #region Constructors

    private CrestMonogramStyle(Kinds kind, string name, string title, CrestVocabulary drawnSince) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
    }

    #endregion

    #region Actions - Lookup

    public static CrestMonogramStyle? Named(string? name) => All.FirstOrDefault(monogramStyle => monogramStyle.Name == name);

    #endregion
}
