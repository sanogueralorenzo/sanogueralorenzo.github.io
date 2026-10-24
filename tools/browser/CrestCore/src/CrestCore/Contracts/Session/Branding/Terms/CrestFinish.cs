namespace CrestCore.Contracts;

/// The surface a crest is rendered with.
public sealed class CrestFinish {
    #region Types

    /// Each platform paints each finish, so its renderer switches over the kind.
    public enum Kinds { Flat, Sheen, Embossed }

    #endregion

    #region Variables

    public static readonly CrestFinish Flat = new(Kinds.Flat, "flat", "Flat", CrestVocabulary.Baseline);
    public static readonly CrestFinish Sheen = new(Kinds.Sheen, "sheen", "Sheen", CrestVocabulary.Studio, hasAngle: true);
    public static readonly CrestFinish Embossed = new(Kinds.Embossed, "embossed", "Embossed", CrestVocabulary.Studio);

    public static IReadOnlyList<CrestFinish> All { get; } = [Flat, Sheen, Embossed];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The term's name in the Studio.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws it.
    public CrestVocabulary DrawnSince { get; }

    /// Whether the finish's light falls from a direction, and so reads the crest's sheen angle.
    public bool HasAngle { get; }

    #endregion

    #region Constructors

    private CrestFinish(Kinds kind, string name, string title, CrestVocabulary drawnSince, bool hasAngle = false) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
        HasAngle = hasAngle;
    }

    #endregion

    #region Actions - Lookup

    public static CrestFinish? Named(string? name) => All.FirstOrDefault(finish => finish.Name == name);

    #endregion
}
