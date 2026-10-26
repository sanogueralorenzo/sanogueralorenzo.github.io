namespace CrestCore.Contracts;

/// The look a Space an import brings wears: the branding it came with in
/// today's units and within the core's ranges, announcing the vocabulary it
/// draws with, or the legacy look of its accent and symbol when it came with
/// none.
public sealed partial record SpaceBranding {
    #region Static Variables

    /// The crest layers an imported composition addresses unless it chooses
    /// otherwise: the backplate, second field, ordinary, trim, figure and edge.
    private static readonly int[] ImportedLayers = [1, 1, 2, 1, 2, 1];

    #endregion

    #region Actions - Imports

    /// `branding` as a Space keeps it, or the legacy look of `accent` and
    /// `symbol` when there is none.
    internal static SpaceBranding Kept(SpaceBranding? branding, SpaceAccent accent, string symbol) =>
        Normalized(branding ?? Legacy(accent, symbol));

    /// The neutral look a Space from another browser wears when it brought no
    /// colors, with the crest figure `symbol` suggests.
    internal static SpaceBranding NeutralImport(string symbol) =>
        Neutral with { Crest = Neutral.Crest with { Symbol = LegacyFigure(symbol) } };

    /// A look painted with another browser's `colors`, keeping controls
    /// readable unless `readabilityFade` says otherwise, with a plain mountain
    /// crest unless `figure` names another. An imported look keeps controls
    /// readable with `LegacyReadabilityFade` unless it names its own.
    internal static SpaceBranding Painted(IReadOnlyList<BrandColor> colors, SpaceBannerPattern pattern, double strength,
        double readabilityFade, SpaceThemeMode theme, double gradientAngle, bool showsTexture, CrestSymbol? figure = null) {
        var crest = SpaceCrest.PlainField(CrestBackplate.Shield, figure ?? CrestSymbol.Mountain, CrestTrim.None, ImportedLayers,
            trimWeight: 1, chargeScale: 1);
        return new(new(colors), pattern, strength, readabilityFade, readabilityFade > 0, theme, gradientAngle, showsTexture,
            SpaceIconStyle.SimpleSymbol, SymbolColor: null, crest, BaselineRenderingVersion, FolderColorIntensity: 0,
            SpaceTextColorMode.Automatic, HasCustomAppearance: null);
    }

    #endregion
}
