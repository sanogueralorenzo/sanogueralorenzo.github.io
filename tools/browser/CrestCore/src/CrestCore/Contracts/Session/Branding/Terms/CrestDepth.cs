namespace CrestCore.Contracts;

/// How far a crest stands off the banner.
public sealed class CrestDepth {
    #region Types

    /// Each platform casts each depth's shadow, so its renderer switches over the kind.
    public enum Kinds { None, Soft, Lifted }

    #endregion

    #region Variables

    public static readonly CrestDepth None = new(Kinds.None, "none", "None", CrestVocabulary.Baseline);
    public static readonly CrestDepth Soft = new(Kinds.Soft, "soft", "Soft", CrestVocabulary.Studio);
    public static readonly CrestDepth Lifted = new(Kinds.Lifted, "lifted", "Lifted", CrestVocabulary.Studio);

    public static IReadOnlyList<CrestDepth> All { get; } = [None, Soft, Lifted];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The term's name in the Studio.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws it.
    public CrestVocabulary DrawnSince { get; }

    #endregion

    #region Constructors

    private CrestDepth(Kinds kind, string name, string title, CrestVocabulary drawnSince) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
    }

    #endregion

    #region Actions - Lookup

    public static CrestDepth? Named(string? name) => All.FirstOrDefault(depth => depth.Name == name);

    #endregion
}
