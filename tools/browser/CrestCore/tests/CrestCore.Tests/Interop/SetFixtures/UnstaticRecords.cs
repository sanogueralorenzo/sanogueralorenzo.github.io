using CrestCore.Contracts;

namespace CrestCore.Tests.Unstatic;

/// `Statics.Gauge` without its statics, which never cross the wire.
public sealed record Gauge(string Label, double Level, BrandColor? Tint) : Change {
    #region Variables

    [Resolved]
    public double Share => Level / 100;

    #endregion
}
