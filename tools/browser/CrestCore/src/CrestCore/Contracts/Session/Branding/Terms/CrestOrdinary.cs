namespace CrestCore.Contracts;

/// The band or cross laid over a crest's field.
public sealed class CrestOrdinary {
    #region Types

    /// Each platform draws each band's path, so its renderer switches over the kind.
    public enum Kinds { None, Pale, Fess, Bend, Chevron, Cross, Saltire, Chief, Bordure, Pall, Pile, Canton, Roundel }

    #endregion

    #region Variables

    public static readonly CrestOrdinary None = new(Kinds.None, "none", "None", CrestVocabulary.Baseline);
    public static readonly CrestOrdinary Pale = new(Kinds.Pale, "pale", "Pale", CrestVocabulary.Baseline);
    public static readonly CrestOrdinary Fess = new(Kinds.Fess, "fess", "Fess", CrestVocabulary.Baseline);
    public static readonly CrestOrdinary Bend = new(Kinds.Bend, "bend", "Bend", CrestVocabulary.Baseline);
    public static readonly CrestOrdinary Chevron = new(Kinds.Chevron, "chevron", "Chevron", CrestVocabulary.Baseline);
    public static readonly CrestOrdinary Cross = new(Kinds.Cross, "cross", "Cross", CrestVocabulary.Baseline);
    public static readonly CrestOrdinary Saltire = new(Kinds.Saltire, "saltire", "Saltire", CrestVocabulary.Baseline);
    public static readonly CrestOrdinary Chief = new(Kinds.Chief, "chief", "Chief", CrestVocabulary.Baseline);
    public static readonly CrestOrdinary Bordure = new(Kinds.Bordure, "bordure", "Bordure", CrestVocabulary.Baseline);
    public static readonly CrestOrdinary Pall = new(Kinds.Pall, "pall", "Pall", CrestVocabulary.Studio);
    public static readonly CrestOrdinary Pile = new(Kinds.Pile, "pile", "Pile", CrestVocabulary.Studio);
    public static readonly CrestOrdinary Canton = new(Kinds.Canton, "canton", "Canton", CrestVocabulary.Studio);
    public static readonly CrestOrdinary Roundel = new(Kinds.Roundel, "roundel", "Roundel", CrestVocabulary.Studio);

    public static IReadOnlyList<CrestOrdinary> All { get; } =
        [None, Pale, Fess, Bend, Chevron, Cross, Saltire, Chief, Bordure, Pall, Pile, Canton, Roundel];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The band's name in the gallery.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws the band.
    public CrestVocabulary DrawnSince { get; }

    #endregion

    #region Constructors

    private CrestOrdinary(Kinds kind, string name, string title, CrestVocabulary drawnSince) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
    }

    #endregion

    #region Actions - Lookup

    public static CrestOrdinary? Named(string? name) => All.FirstOrDefault(ordinary => ordinary.Name == name);

    #endregion
}
