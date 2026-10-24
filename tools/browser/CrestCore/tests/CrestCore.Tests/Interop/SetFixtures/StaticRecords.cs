using CrestCore.Contracts;

namespace CrestCore.Tests.Statics;

/// A gauge with a limit, a full scale and two named readings, and the share of
/// the scale it resolves.
public sealed record Gauge(string Label, double Level, BrandColor? Tint) : Change {
    #region Static Variables

    public const int Limit = 3;
    public const double Full = 100;

    public static Gauge Empty { get; } = new("", 0, null);
    public static Gauge Tinted { get; } = new("tinted", 25, new(0.5, 0.25, 0.125));

    #endregion

    #region Variables

    [Resolved]
    public double Share => Level / Full;

    #endregion
}
