namespace CrestCore.Contracts;

/// <summary>
/// The composition of a Space's crest. Layer color indices point into the crest's own
/// <see cref="Palette"/> when it has one, else into the Space's colors. A
/// <see cref="Charge"/> replaces the heraldic <see cref="Symbol"/> as the figure drawn.
/// </summary>
public sealed record SpaceCrest(
    CrestBackplate Backplate,
    CrestFieldDivision FieldDivision,
    CrestOrdinary Ordinary,
    CrestTrim Trim,
    CrestSymbol Symbol,
    CrestChargeLayout ChargeLayout,
    int BackplateColorIndex,
    int SecondaryFieldColorIndex,
    int OrdinaryColorIndex,
    int TrimColorIndex,
    int SymbolColorIndex,
    string? StartingPresetId,
    int EdgeColorIndex,
    ColorPalette? Palette,
    CrestCharge? Charge,
    double PlateScale,
    double EdgeWidth,
    int DivisionCount,
    CrestFinish Finish,
    double OrdinaryWidth,
    double TrimWeight,
    int TrimDetail,
    double ChargeScale,
    double ChargeOffset,
    CrestChargeWeight ChargeWeight,
    double SheenAngle,
    int SealTeeth,
    bool ShowsOutline,
    CrestDepth Depth) {
    #region Static Variables

    /// How many pieces a counted field division draws unless set.
    public const int DefaultDivisionCount = 4;

    /// How much detail a counted trim draws unless set.
    public const int DefaultTrimDetail = 12;

    #endregion

    #region Actions - Compositions

    /// <summary>A plain-field crest with no ordinary, charged with <paramref name="figure"/>.
    /// <paramref name="layers"/> addresses, in order, the backplate, the second field, the
    /// ordinary, the trim, the figure and the edge; every other parameter is neutral.</summary>
    public static SpaceCrest PlainField(CrestBackplate backplate, CrestSymbol figure, CrestTrim trim, IReadOnlyList<int> layers,
        double trimWeight, double chargeScale) {
        ArgumentNullException.ThrowIfNull(layers);
        return new(backplate, CrestFieldDivision.Plain, CrestOrdinary.None, trim, figure, CrestChargeLayout.Single,
            BackplateColorIndex: layers[0], SecondaryFieldColorIndex: layers[1], OrdinaryColorIndex: layers[2], TrimColorIndex: layers[3],
            SymbolColorIndex: layers[4], StartingPresetId: null, EdgeColorIndex: layers[5], Palette: null, Charge: null, PlateScale: 1,
            EdgeWidth: 0, DivisionCount: DefaultDivisionCount, CrestFinish.Flat, OrdinaryWidth: 1, trimWeight,
            TrimDetail: DefaultTrimDetail, chargeScale, ChargeOffset: 0, CrestChargeWeight.Bold, SheenAngle: 45, SealTeeth: 12,
            ShowsOutline: false, CrestDepth.None);
    }

    #endregion
}
