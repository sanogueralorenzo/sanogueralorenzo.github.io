namespace CrestCore.Contracts;

/// The shape a crest is drawn on.
public sealed class CrestBackplate {
    #region Types

    /// Each platform draws each shape's outline, so its renderer switches over the kind.
    public enum Kinds { None, Circle, Shield, FrenchShield, Diamond, Seal, Hexagon, Octagon, RoundedSquare, Oval, Banner, Badge }

    #endregion

    #region Variables

    public static readonly CrestBackplate None = new(Kinds.None, "none", "None", CrestVocabulary.Baseline);
    public static readonly CrestBackplate Circle = new(Kinds.Circle, "circle", "Round", CrestVocabulary.Baseline);
    public static readonly CrestBackplate Shield = new(Kinds.Shield, "shield", "Shield", CrestVocabulary.Baseline);
    public static readonly CrestBackplate FrenchShield = new(Kinds.FrenchShield, "frenchShield", "French Shield", CrestVocabulary.Studio);
    public static readonly CrestBackplate Diamond = new(Kinds.Diamond, "diamond", "Lozenge", CrestVocabulary.Baseline);
    public static readonly CrestBackplate Seal = new(Kinds.Seal, "seal", "Seal", CrestVocabulary.Baseline, hasTeeth: true);
    public static readonly CrestBackplate Hexagon = new(Kinds.Hexagon, "hexagon", "Hexagon", CrestVocabulary.Baseline);
    public static readonly CrestBackplate Octagon = new(Kinds.Octagon, "octagon", "Octagon", CrestVocabulary.Customization);
    public static readonly CrestBackplate RoundedSquare = new(Kinds.RoundedSquare, "roundedSquare", "Rounded Square",
        CrestVocabulary.Customization);
    public static readonly CrestBackplate Oval = new(Kinds.Oval, "oval", "Oval", CrestVocabulary.Studio);
    public static readonly CrestBackplate Banner = new(Kinds.Banner, "banner", "Banner", CrestVocabulary.Studio);
    public static readonly CrestBackplate Badge = new(Kinds.Badge, "badge", "Badge", CrestVocabulary.Studio);

    public static IReadOnlyList<CrestBackplate> All { get; } =
        [None, Circle, Shield, FrenchShield, Diamond, Seal, Hexagon, Octagon, RoundedSquare, Oval, Banner, Badge];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The shape's name in the gallery.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws the shape.
    public CrestVocabulary DrawnSince { get; }

    /// Whether the shape's edge is scalloped, and so reads the crest's seal teeth.
    public bool HasTeeth { get; }

    #endregion

    #region Constructors

    private CrestBackplate(Kinds kind, string name, string title, CrestVocabulary drawnSince, bool hasTeeth = false) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
        HasTeeth = hasTeeth;
    }

    #endregion

    #region Actions - Lookup

    public static CrestBackplate? Named(string? name) => All.FirstOrDefault(backplate => backplate.Name == name);

    #endregion
}
