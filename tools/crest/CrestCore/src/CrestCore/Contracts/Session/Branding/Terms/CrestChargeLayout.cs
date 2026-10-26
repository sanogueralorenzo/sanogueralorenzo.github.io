namespace CrestCore.Contracts;

/// How many figures a crest repeats, and how.
public sealed class CrestChargeLayout {
    #region Types

    /// Each platform places each arrangement's figures, so its renderer switches over the kind.
    public enum Kinds { Single, Paired, Trio, Quad, Ring }

    #endregion

    #region Variables

    public static readonly CrestChargeLayout Single = new(Kinds.Single, "single", "One", CrestVocabulary.Baseline);
    public static readonly CrestChargeLayout Paired = new(Kinds.Paired, "paired", "Two", CrestVocabulary.Baseline);
    public static readonly CrestChargeLayout Trio = new(Kinds.Trio, "trio", "Three", CrestVocabulary.Baseline);
    public static readonly CrestChargeLayout Quad = new(Kinds.Quad, "quad", "Four", CrestVocabulary.Studio);
    public static readonly CrestChargeLayout Ring = new(Kinds.Ring, "ring", "Ring", CrestVocabulary.Studio);

    public static IReadOnlyList<CrestChargeLayout> All { get; } = [Single, Paired, Trio, Quad, Ring];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The term's name in the Studio.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws it.
    public CrestVocabulary DrawnSince { get; }

    #endregion

    #region Constructors

    private CrestChargeLayout(Kinds kind, string name, string title, CrestVocabulary drawnSince) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
    }

    #endregion

    #region Actions - Lookup

    public static CrestChargeLayout? Named(string? name) => All.FirstOrDefault(chargeLayout => chargeLayout.Name == name);

    #endregion
}
