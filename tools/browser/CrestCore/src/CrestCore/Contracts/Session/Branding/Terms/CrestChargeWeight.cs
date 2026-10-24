namespace CrestCore.Contracts;

/// The stroke weight of a crest's figure.
public sealed class CrestChargeWeight {
    #region Types

    /// Each platform maps each weight to its own font weight, so its renderer switches over the kind.
    public enum Kinds { Light, Regular, Bold }

    #endregion

    #region Variables

    public static readonly CrestChargeWeight Light = new(Kinds.Light, "light", "Light", CrestVocabulary.Studio);
    public static readonly CrestChargeWeight Regular = new(Kinds.Regular, "regular", "Regular", CrestVocabulary.Studio);
    public static readonly CrestChargeWeight Bold = new(Kinds.Bold, "bold", "Bold", CrestVocabulary.Baseline);

    public static IReadOnlyList<CrestChargeWeight> All { get; } = [Light, Regular, Bold];

    public Kinds Kind { get; }
    public string Name { get; }

    /// The term's name in the Studio.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws it.
    public CrestVocabulary DrawnSince { get; }

    #endregion

    #region Constructors

    private CrestChargeWeight(Kinds kind, string name, string title, CrestVocabulary drawnSince) {
        Kind = kind;
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
    }

    #endregion

    #region Actions - Lookup

    public static CrestChargeWeight? Named(string? name) => All.FirstOrDefault(chargeWeight => chargeWeight.Name == name);

    #endregion
}
