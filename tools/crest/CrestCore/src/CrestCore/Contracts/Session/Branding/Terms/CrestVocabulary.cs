namespace CrestCore.Contracts;

/// A version of the crest and banner vocabulary every build that draws it
/// draws alike. A look announces the newest vocabulary any of its terms
/// needs, so an older reader of a synced look knows what it cannot draw.
public sealed class CrestVocabulary {
    #region Variables

    /// The vocabulary every shipped build draws.
    public static readonly CrestVocabulary Baseline = new(name: "baseline", version: SpaceBranding.BaselineRenderingVersion);
    /// The vocabulary that added the expanded heraldic charges.
    public static readonly CrestVocabulary ExpandedCharges = new(name: "expandedCharges", version: 3);
    /// The vocabulary that added the customization surfaces and backplates.
    public static readonly CrestVocabulary Customization = new(name: "customization", version: 4);
    /// The Crest Studio vocabulary: parametric shapes, own tinctures, custom
    /// charges, finishes and depth.
    public static readonly CrestVocabulary Studio = new(name: "studio", version: 5);

    public static IReadOnlyList<CrestVocabulary> All { get; } = [Baseline, ExpandedCharges, Customization, Studio];

    public string Name { get; }

    /// The rendering version a look announces when this is the newest
    /// vocabulary it needs.
    public int Version { get; }

    #endregion

    #region Constructors

    private CrestVocabulary(string name, int version) {
        Name = name;
        Version = version;
    }

    #endregion

    #region Actions - Lookup

    public static CrestVocabulary? Named(string? name) => All.FirstOrDefault(vocabulary => vocabulary.Name == name);

    #endregion
}
