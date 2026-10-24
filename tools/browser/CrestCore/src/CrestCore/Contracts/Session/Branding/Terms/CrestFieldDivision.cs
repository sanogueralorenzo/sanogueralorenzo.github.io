namespace CrestCore.Contracts;

/// How a crest's field is divided.
public sealed class CrestFieldDivision {
    #region Types

    /// Each platform draws each division's geometry, so its renderer switches over the kind.
    public enum Kinds { Plain, PerPale, PerFess, PerBend, PerChevron, Quarterly, PerSaltire, Gyronny, Barry, Paly, Checky }

    #endregion

    #region Variables

    // Titles are one word: they caption gallery cards that already show the division.
    public static readonly CrestFieldDivision Plain = new(Kinds.Plain, "plain", "Plain", CrestVocabulary.Baseline);
    public static readonly CrestFieldDivision PerPale = new(Kinds.PerPale, "perPale", "Vertical", CrestVocabulary.Baseline);
    public static readonly CrestFieldDivision PerFess = new(Kinds.PerFess, "perFess", "Horizontal", CrestVocabulary.Baseline);
    public static readonly CrestFieldDivision PerBend = new(Kinds.PerBend, "perBend", "Diagonal", CrestVocabulary.Baseline);
    public static readonly CrestFieldDivision PerChevron = new(Kinds.PerChevron, "perChevron", "Chevron", CrestVocabulary.Baseline);
    public static readonly CrestFieldDivision Quarterly = new(Kinds.Quarterly, "quarterly", "Quartered", CrestVocabulary.Baseline);
    public static readonly CrestFieldDivision PerSaltire = new(Kinds.PerSaltire, "perSaltire", "Crossed", CrestVocabulary.Studio);
    public static readonly CrestFieldDivision Gyronny = new(Kinds.Gyronny, "gyronny", "Wedges", CrestVocabulary.Studio, isCounted: true);
    public static readonly CrestFieldDivision Barry = new(Kinds.Barry, "barry", "Bars", CrestVocabulary.Studio, isCounted: true);
    public static readonly CrestFieldDivision Paly = new(Kinds.Paly, "paly", "Stripes", CrestVocabulary.Studio, isCounted: true);
    public static readonly CrestFieldDivision Checky = new(Kinds.Checky, "checky", "Checks", CrestVocabulary.Studio, isCounted: true);

    public static IReadOnlyList<CrestFieldDivision> All { get; } =
        [Plain, PerPale, PerFess, PerBend, PerChevron, Quarterly, PerSaltire, Gyronny, Barry, Paly, Checky];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The division's name in the gallery.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws the division.
    public CrestVocabulary DrawnSince { get; }

    /// Whether the division repeats a number of pieces, and so reads the
    /// crest's division count.
    public bool IsCounted { get; }

    #endregion

    #region Constructors

    private CrestFieldDivision(Kinds kind, string name, string title, CrestVocabulary drawnSince, bool isCounted = false) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
        IsCounted = isCounted;
    }

    #endregion

    #region Actions - Lookup

    public static CrestFieldDivision? Named(string? name) => All.FirstOrDefault(division => division.Name == name);

    #endregion
}
