using CrestCore.Domain;

namespace CrestCore.Contracts;

/// The range rules for a Space's banner branding. The crest's heraldic vocabulary
/// stays with the native renderer; the core owns the palette size, the banner
/// strengths, the gradient angle, the crest's layer colors pointing at a color
/// that exists, its composition parameters within the ranges the renderer draws
/// and its custom figure, so the branding the core stages for sync is the one
/// every device renders.
public sealed partial record SpaceBranding {
    #region Static Variables

    internal const int MaximumColorCount = 3;
    internal const int MaximumCrestPaletteCount = 6;

    /// The Space color used when a branding record has none.
    internal static BrandColor DefaultColor { get; } = new(0.29, 0.25, 0.58);

    #endregion

    #region Actions - Normalization

    /// The branding with every rule the core owns applied, as every client
    /// writes it: its banner strength in today's units, at most three colors
    /// and never none, strengths, fades and color components within 0 through
    /// 1, the gradient angle within a turn, and crest layers addressing a color
    /// that exists. The crest's own palette is dropped when it holds no color,
    /// its composition parameters stay within the ranges the renderer draws,
    /// and a custom figure that is the crest's own symbol is no custom figure.
    /// It announces the readability and rendering vocabulary its values need.
    internal static SpaceBranding Normalized(SpaceBranding branding) {
        ArgumentNullException.ThrowIfNull(branding);
        branding = branding.InTodaysUnits();
        var colors = branding.Colors.Colors.Take(MaximumColorCount).Select(NormalizedColor).ToArray();
        if (colors.Length == 0) colors = [DefaultColor];
        var palette = branding.Crest.Palette?.Colors.Take(MaximumCrestPaletteCount).Select(NormalizedColor).ToArray();
        if (palette is { Length: 0 }) palette = null;
        int layers = LayerColorCount(palette?.Length, colors.Length);
        var crest = branding.Crest;
        return Announced(branding with {
            Colors = new(colors),
            BannerStrength = Unit(branding.BannerStrength),
            ReadabilityFade = Unit(branding.ReadabilityFade),
            GradientAngle = NormalizedAngle(branding.GradientAngle),
            FolderColorIntensity = Unit(branding.FolderColorIntensity),
            SymbolColor = branding.SymbolColor is { } symbol ? NormalizedColor(symbol) : null,
            Crest = crest with {
                Palette = palette is null ? null : new(palette),
                BackplateColorIndex = LayerIndex(crest.BackplateColorIndex, layers),
                SecondaryFieldColorIndex = LayerIndex(crest.SecondaryFieldColorIndex, layers),
                OrdinaryColorIndex = LayerIndex(crest.OrdinaryColorIndex, layers),
                TrimColorIndex = LayerIndex(crest.TrimColorIndex, layers),
                SymbolColorIndex = LayerIndex(crest.SymbolColorIndex, layers),
                EdgeColorIndex = LayerIndex(crest.EdgeColorIndex, layers),
                Charge = NormalizedCharge(crest.Charge, crest.Symbol),
                PlateScale = CrestMeasure.PlateScale.Clamped(crest.PlateScale),
                EdgeWidth = CrestMeasure.EdgeWidth.Clamped(crest.EdgeWidth),
                DivisionCount = CrestMeasure.DivisionCount.Clamped(crest.DivisionCount),
                OrdinaryWidth = CrestMeasure.OrdinaryWidth.Clamped(crest.OrdinaryWidth),
                TrimWeight = CrestMeasure.TrimWeight.Clamped(crest.TrimWeight),
                TrimDetail = CrestMeasure.TrimDetail.Clamped(crest.TrimDetail),
                ChargeScale = CrestMeasure.ChargeScale.Clamped(crest.ChargeScale),
                ChargeOffset = CrestMeasure.ChargeOffset.Clamped(crest.ChargeOffset),
                SheenAngle = CrestMeasure.SheenAngle.Clamped(crest.SheenAngle),
                SealTeeth = CrestMeasure.SealTeeth.Clamped(crest.SealTeeth)
            }
        });
    }

    /// `look` with the readability and rendering vocabulary it announces worked
    /// out from its values.
    internal static SpaceBranding Announced(SpaceBranding look) {
        ArgumentNullException.ThrowIfNull(look);
        return look with { KeepsControlsReadable = look.ReadabilityFade > 0, RenderingVersion = NeededRenderingVersion(look) };
    }

    /// A crest's custom figure as the renderer draws it: names and letters
    /// trimmed, one emoji, a monogram of at most two capitals, nothing drawn in
    /// place of an empty one, and none at all when it is the crest's own symbol.
    private static CrestCharge? NormalizedCharge(CrestCharge? charge, CrestSymbol symbol) {
        if (charge is null) return null;
        var figure = charge.Kind.Normalized(charge);
        return figure.Kind == CrestChargeKind.Heraldic && figure.Symbol == symbol ? null : figure;
    }

    /// A strength, fade, intensity or color component, kept within 0 through 1.
    /// A value that is not a number falls back to `fallback`.
    private static double Unit(double value, double fallback = 0) => double.IsFinite(value) ? Math.Clamp(value, 0, 1) : fallback;

    /// Degrees in [0, 360).
    private static double NormalizedAngle(double angle) {
        if (!double.IsFinite(angle)) return 0;
        double remainder = angle % 360;
        return remainder >= 0 ? remainder : remainder + 360;
    }

    /// How many colors a crest's layer indices can address: its own palette
    /// when it has one, else the Space's colors, and never fewer than one.
    private static int LayerColorCount(int? crestPaletteCount, int spaceColorCount) =>
        Math.Max(crestPaletteCount ?? spaceColorCount, 1);

    /// A layer index outside the addressable colors falls back to the first.
    private static int LayerIndex(int index, int colorCount) => index >= 0 && index < colorCount ? index : 0;

    private static BrandColor NormalizedColor(BrandColor color) =>
        new(Unit(color.Red), Unit(color.Green), Unit(color.Blue), Unit(color.Alpha, 1));

    #endregion

    #region Actions - Rendering vocabulary

    /// The rendering vocabulary `branding` needs, which is the version it
    /// announces: the newest vocabulary any of its terms is drawn since, and
    /// the Studio's when it sets a Studio parameter or a color of its own.
    /// Every Apple client computes it this way when it writes a branding.
    internal static int NeededRenderingVersion(SpaceBranding branding) {
        ArgumentNullException.ThrowIfNull(branding);
        var crest = branding.Crest;
        CrestVocabulary[] needed = [
            branding.BannerPattern.DrawnSince, crest.Symbol.DrawnSince, crest.Backplate.DrawnSince, crest.FieldDivision.DrawnSince,
            crest.Ordinary.DrawnSince, crest.Trim.DrawnSince, crest.ChargeLayout.DrawnSince, crest.Finish.DrawnSince,
            crest.Depth.DrawnSince, crest.ChargeWeight.DrawnSince,
            branding.SymbolColor is null ? CrestVocabulary.Baseline : CrestVocabulary.Customization,
            UsesStudioParameters(crest) ? CrestVocabulary.Studio : CrestVocabulary.Baseline
        ];
        return needed.Max(vocabulary => vocabulary.Version);
    }

    /// Whether the crest moves a measure only the Studio vocabulary draws off
    /// its default, draws an outline, or wears colors or a figure of its own.
    private static bool UsesStudioParameters(SpaceCrest crest) =>
        crest.Palette is not null || crest.Charge is not null || crest.ShowsOutline
        || CrestMeasure.All.Any(measure => measure.IsMoved(crest));

    #endregion
}
