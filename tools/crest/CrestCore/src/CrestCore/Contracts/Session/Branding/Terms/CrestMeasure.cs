namespace CrestCore.Contracts;

/// A number that sizes, counts or turns part of a crest: the range the
/// renderer draws it in, the value it takes unless set, and the crests it
/// shapes at all.
public sealed class CrestMeasure {
    #region Variables

    public static readonly CrestMeasure PlateScale = new("plateScale", 0.7, 1.15, 1, crest => crest.PlateScale);
    public static readonly CrestMeasure EdgeWidth = new("edgeWidth", 0, 1, 0, crest => crest.EdgeWidth);
    public static readonly CrestMeasure DivisionCount = new("divisionCount", 2, 8, SpaceCrest.DefaultDivisionCount, crest => crest.DivisionCount,
        crest => crest.FieldDivision.IsCounted, isCount: true);
    public static readonly CrestMeasure OrdinaryWidth = new("ordinaryWidth", 0.5, 1.6, 1, crest => crest.OrdinaryWidth);
    public static readonly CrestMeasure TrimWeight = new("trimWeight", 0.5, 2, 1, crest => crest.TrimWeight);
    public static readonly CrestMeasure TrimDetail = new("trimDetail", 6, 24, SpaceCrest.DefaultTrimDetail, crest => crest.TrimDetail,
        crest => crest.Trim.IsCounted, isCount: true);
    public static readonly CrestMeasure ChargeScale = new("chargeScale", 0.6, 1.5, 1, crest => crest.ChargeScale);
    public static readonly CrestMeasure ChargeOffset = new("chargeOffset", -0.2, 0.2, 0, crest => crest.ChargeOffset);
    public static readonly CrestMeasure SheenAngle = new("sheenAngle", 0, 360, 45, crest => crest.SheenAngle);
    public static readonly CrestMeasure SealTeeth = new("sealTeeth", 6, 24, 12, crest => crest.SealTeeth,
        crest => crest.Backplate.HasTeeth, isCount: true);

    public static IReadOnlyList<CrestMeasure> All { get; } =
        [PlateScale, EdgeWidth, DivisionCount, OrdinaryWidth, TrimWeight, TrimDetail, ChargeScale, ChargeOffset, SheenAngle, SealTeeth];

    public string Name { get; }
    public double Minimum { get; }
    public double Maximum { get; }

    /// The value a crest takes unless set, and which the Studio vocabulary is
    /// needed to draw it away from.
    public double Default { get; }

    /// Whether the measure counts whole pieces rather than sizing them.
    public bool IsCount { get; }

    private readonly Func<SpaceCrest, double> value;
    private readonly Func<SpaceCrest, bool> shapes;

    #endregion

    #region Constructors

    private CrestMeasure(string name, double minimum, double maximum, double defaultValue, Func<SpaceCrest, double> value,
        Func<SpaceCrest, bool>? shapes = null, bool isCount = false) {
        Name = name;
        Minimum = minimum;
        Maximum = maximum;
        Default = defaultValue;
        IsCount = isCount;
        this.value = value;
        this.shapes = shapes ?? (_ => true);
    }

    #endregion

    #region Actions - Lookup

    public static CrestMeasure? Named(string? name) => All.FirstOrDefault(measure => measure.Name == name);

    #endregion

    #region Actions - Values

    /// `measure` within the range; one that is not a number takes the default.
    public double Clamped(double measure) => double.IsFinite(measure) ? Math.Clamp(measure, Minimum, Maximum) : Default;

    /// A count within the range.
    public int Clamped(int count) => Math.Clamp(count, (int)Minimum, (int)Maximum);

    /// Whether `crest` draws this measure away from its default.
    public bool IsMoved(SpaceCrest crest) {
        ArgumentNullException.ThrowIfNull(crest);
        return shapes(crest) && value(crest) != Default;
    }

    #endregion
}
