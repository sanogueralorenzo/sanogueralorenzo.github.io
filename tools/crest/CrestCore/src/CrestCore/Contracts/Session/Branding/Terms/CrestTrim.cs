namespace CrestCore.Contracts;

/// The border drawn around a crest.
public sealed class CrestTrim {
    #region Types

    /// Each platform draws each border, so its renderer switches over the kind.
    public enum Kinds { None, Shield, Line, DoubleLine, Laurel, Sunburst, DoubleRing, Seal, Beaded }

    #endregion

    #region Variables

    public static readonly CrestTrim None = new(Kinds.None, "none", "None", CrestVocabulary.Baseline);
    public static readonly CrestTrim Shield = new(Kinds.Shield, "shield", "Shield", CrestVocabulary.Baseline);
    public static readonly CrestTrim Line = new(Kinds.Line, "line", "Line", CrestVocabulary.Studio);
    public static readonly CrestTrim DoubleLine = new(Kinds.DoubleLine, "doubleLine", "Double Line", CrestVocabulary.Studio);
    public static readonly CrestTrim Laurel = new(Kinds.Laurel, "laurel", "Laurel", CrestVocabulary.Baseline);
    public static readonly CrestTrim Sunburst = new(Kinds.Sunburst, "sunburst", "Sunburst", CrestVocabulary.Baseline, isCounted: true);
    public static readonly CrestTrim DoubleRing = new(Kinds.DoubleRing, "doubleRing", "Double Ring", CrestVocabulary.Baseline);
    public static readonly CrestTrim Seal = new(Kinds.Seal, "seal", "Seal", CrestVocabulary.Baseline);
    public static readonly CrestTrim Beaded = new(Kinds.Beaded, "beaded", "Beaded", CrestVocabulary.Studio, isCounted: true);

    public static IReadOnlyList<CrestTrim> All { get; } = [None, Shield, Line, DoubleLine, Laurel, Sunburst, DoubleRing, Seal, Beaded];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The border's name in the gallery.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws the border.
    public CrestVocabulary DrawnSince { get; }

    /// Whether the border is made of repeated elements, and so reads the
    /// crest's trim detail.
    public bool IsCounted { get; }

    #endregion

    #region Constructors

    private CrestTrim(Kinds kind, string name, string title, CrestVocabulary drawnSince, bool isCounted = false) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
        IsCounted = isCounted;
    }

    #endregion

    #region Actions - Lookup

    public static CrestTrim? Named(string? name) => All.FirstOrDefault(trim => trim.Name == name);

    #endregion
}
