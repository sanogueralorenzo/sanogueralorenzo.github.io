using System.Text.Json.Nodes;

using CrestCore.Contracts;
using CrestCore.Domain;

namespace CrestCore.Application;

internal sealed partial record SpacePayload {
    #region Static Variables

    /// Branding stored before rendering versions were recorded is version one.
    private const int FirstRenderingVersion = 1;

    #endregion

    #region Actions - Branding

    /// A branding as every client reads it: its colors, strength and crest
    /// are required, a term a client cannot name takes its default, and every
    /// value is kept within the range the renderer draws. It keeps the
    /// rendering version it was written with, so the core's rules put a
    /// branding from before the baseline vocabulary in today's units once, and
    /// leave one already in them as it is.
    private static SpaceBranding ReadBranding(SyncPayloadReader value) {
        bool keepsReadable = value.OptionalFlag("keepsControlsReadable") ?? true;
        double fade = value.OptionalNumber("readabilityFade") ?? (keepsReadable ? SpaceBranding.LegacyReadabilityFade : 0);
        int version = Whole(value.OptionalInteger("renderingVersion") ?? FirstRenderingVersion);
        var colors = value.Array("colors").Select(Color).ToArray();
        var branding = new SpaceBranding(new(colors),
            SpaceBannerPattern.Named(value.TolerantText("bannerPattern")) ?? SpaceBannerPattern.Solid,
            value.Number("bannerStrength"), fade, fade > 0,
            SpaceThemeMode.Named(value.TolerantText("themeMode")) ?? SpaceThemeMode.Banner,
            value.OptionalNumber("gradientAngle") ?? 0, value.OptionalFlag("showsTexture") ?? false,
            SpaceIconStyle.Named(value.TolerantText("iconStyle")) ?? SpaceIconStyle.SimpleSymbol,
            value.Value["symbolColor"] is { } symbolColor ? Color(symbolColor) : null,
            ReadCrest(value.Nested("crest")), version, value.TolerantNumber("folderColorIntensity") ?? 0,
            SpaceTextColorMode.Named(value.TolerantText("textColorMode")) ?? SpaceTextColorMode.Automatic,
            value.OptionalFlag("hasCustomAppearance"));
        return SpaceBranding.Normalized(branding);
    }

    /// A crest as every client reads it: each member it cannot read takes its
    /// neutral value, and a figure it cannot read is none.
    private static SpaceCrest ReadCrest(SyncPayloadReader value) {
        int Index(string key, int fallback = 0) => Whole(value.TolerantInteger(key) ?? fallback);
        double Measure(CrestMeasure measure) => value.TolerantNumber(measure.Name) ?? measure.Default;
        int Count(CrestMeasure measure) => Whole(value.TolerantInteger(measure.Name) ?? (int)measure.Default);
        return new(CrestBackplate.Named(value.TolerantText("backplate")) ?? CrestBackplate.Shield,
            CrestFieldDivision.Named(value.TolerantText("fieldDivision")) ?? CrestFieldDivision.Plain,
            CrestOrdinary.Named(value.TolerantText("ordinary")) ?? CrestOrdinary.None,
            CrestTrim.Named(value.TolerantText("trim")) ?? CrestTrim.None,
            CrestSymbol.Named(value.TolerantText("symbol")) ?? CrestSymbol.Fallback,
            CrestChargeLayout.Named(value.TolerantText("chargeLayout")) ?? CrestChargeLayout.Single,
            Index("backplateColorIndex"), Index("secondaryFieldColorIndex"), Index("ordinaryColorIndex"), Index("trimColorIndex"),
            Index("symbolColorIndex"), value.TolerantText("startingPresetID"), Index("edgeColorIndex", Index("trimColorIndex")),
            Palette(value.Value["palette"]), Charge(value.Value["charge"]),
            Measure(CrestMeasure.PlateScale), Measure(CrestMeasure.EdgeWidth), Count(CrestMeasure.DivisionCount),
            CrestFinish.Named(value.TolerantText("finish")) ?? CrestFinish.Flat,
            Measure(CrestMeasure.OrdinaryWidth), Measure(CrestMeasure.TrimWeight), Count(CrestMeasure.TrimDetail),
            Measure(CrestMeasure.ChargeScale), Measure(CrestMeasure.ChargeOffset),
            CrestChargeWeight.Named(value.TolerantText("chargeWeight")) ?? CrestChargeWeight.Bold,
            Measure(CrestMeasure.SheenAngle), Count(CrestMeasure.SealTeeth), value.TolerantFlag("showsOutline") ?? false,
            CrestDepth.Named(value.TolerantText("depth")) ?? CrestDepth.None);
    }

    /// A crest's own palette, or null when it has none every client reads.
    private static ColorPalette? Palette(JsonNode? node) {
        if (node is null) return null;
        try {
            return new([.. (node as JsonArray ?? throw new UnreadableSyncPayloadException()).Select(Color)]);
        } catch (UnreadableSyncPayloadException) {
            return null;
        }
    }

    /// A crest's custom figure, or null when it has none every client reads. A
    /// kind no client knows draws nothing; a heraldic figure no client knows is
    /// the mountain; a monogram is serif unless it says.
    private static CrestCharge? Charge(JsonNode? node) {
        if (node is not JsonObject) return null;
        try {
            var value = new SyncPayloadReader(node, SyncPayloadForm.Journal);
            string text = value.OptionalText("value") ?? "";
            var kind = CrestChargeKind.Named(value.TolerantText("kind")) ?? CrestChargeKind.None;
            return kind.Kind switch {
                CrestChargeKind.Kinds.Heraldic => new(kind, CrestSymbol.Named(text) ?? CrestSymbol.Fallback),
                CrestChargeKind.Kinds.System or CrestChargeKind.Kinds.Emoji => new(kind, Text: text),
                CrestChargeKind.Kinds.Monogram => new(kind, Text: text,
                    Style: CrestMonogramStyle.Named(value.TolerantText("style")) ?? CrestMonogramStyle.Serif),
                _ => new(CrestChargeKind.None)
            };
        } catch (UnreadableSyncPayloadException) {
            return null;
        }
    }

    /// A color a record spells by component, or by the name of a tincture as
    /// builds before stored colors whole did, each component kept
    /// within 0 through 1 and alpha opaque unless it says.
    internal static BrandColor Color(JsonNode? node) {
        if (node is JsonValue named && named.GetValueKind() == System.Text.Json.JsonValueKind.String
            && Tincture.Named(named.GetValue<string>()) is { } tincture) return tincture.Color;
        var value = new SyncPayloadReader(node, SyncPayloadForm.Journal);
        return new(Unit(value.Number("red")), Unit(value.Number("green")), Unit(value.Number("blue")),
            Unit(value.OptionalNumber("alpha") ?? 1));
    }

    /// A branding as every client writes it.
    private static JsonObject EncodeBranding(SpaceBranding branding) => StoredSessionCodec.Encode(branding);

    private static double Unit(double value) => Math.Clamp(value, 0, 1);

    /// A whole number a client holds in a 64-bit integer, within the range an
    /// index or a count here holds: anything outside it is out of every range.
    private static int Whole(long value) => (int)Math.Clamp(value, int.MinValue, int.MaxValue);

    #endregion
}
