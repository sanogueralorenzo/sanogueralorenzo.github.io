using System.Text.Json.Nodes;

using CrestCore.Contracts;

namespace CrestCore.Application;

internal static partial class StoredSessionCodec {
    #region Variables

    /// Branding stored before rendering versions were recorded is version one.
    private const int FirstRenderingVersion = 1;

    #endregion

    #region Actions - Branding

    /// A Space's branding, with the native reader's defaults for anything missing
    /// and for a term this build cannot name. Colors that are not color records
    /// are left out.
    internal static SpaceBranding DecodeBranding(JsonNode? node) {
        var value = Object(node);
        var fade = OptionalNumber(value[Key.ReadabilityFade]);
        var keepsReadable = Flag(value[Key.KeepsControlsReadable]);
        fade ??= keepsReadable ?? true ? SpaceBranding.LegacyReadabilityFade : 0;
        return new(Palette(value[Key.Colors]) ?? new([]),
            SpaceBannerPattern.Named(Text(value[Key.BannerPattern])) ?? SpaceBannerPattern.Solid,
            OptionalNumber(value[Key.BannerStrength]) ?? 1, fade.Value, keepsReadable ?? fade > 0,
            SpaceThemeMode.Named(Text(value[Key.ThemeMode])) ?? SpaceThemeMode.Banner,
            OptionalNumber(value[Key.GradientAngle]) ?? 0, Flag(value[Key.ShowsTexture]) ?? false,
            SpaceIconStyle.Named(Text(value[Key.IconStyle])) ?? SpaceIconStyle.SimpleSymbol,
            value[Key.SymbolColor] is JsonObject symbolColor ? DecodeColor(symbolColor) : null,
            DecodeCrest(value[Key.Crest] as JsonObject ?? []),
            Integer(value[Key.RenderingVersion]) ?? FirstRenderingVersion,
            OptionalNumber(value[Key.FolderColorIntensity]) ?? 0,
            SpaceTextColorMode.Named(Text(value[Key.TextColorMode])) ?? SpaceTextColorMode.Automatic,
            Flag(value[Key.HasCustomAppearance]));
    }

    internal static JsonObject Encode(SpaceBranding branding) {
        var value = new JsonObject {
            [Key.Colors] = Encode(branding.Colors),
            [Key.BannerPattern] = branding.BannerPattern.Name,
            [Key.BannerStrength] = branding.BannerStrength,
            [Key.ReadabilityFade] = branding.ReadabilityFade,
            [Key.KeepsControlsReadable] = branding.KeepsControlsReadable,
            [Key.ThemeMode] = branding.ThemeMode.Name,
            [Key.GradientAngle] = branding.GradientAngle,
            [Key.ShowsTexture] = branding.ShowsTexture,
            [Key.IconStyle] = branding.IconStyle.Name
        };
        if (branding.SymbolColor is { } symbolColor) value[Key.SymbolColor] = Encode(symbolColor);
        value[Key.Crest] = Encode(branding.Crest);
        value[Key.RenderingVersion] = branding.RenderingVersion;
        value[Key.FolderColorIntensity] = branding.FolderColorIntensity;
        value[Key.TextColorMode] = branding.TextColorMode.Name;
        if (branding.HasCustomAppearance is { } custom) value[Key.HasCustomAppearance] = custom;
        return value;
    }

    /// A crest composition. Missing layer indices read as the first color, the
    /// edge follows the trim, and every other parameter takes its neutral value.
    internal static SpaceCrest DecodeCrest(JsonObject value) {
        int Index(string key, int fallback = 0) => Integer(value[key]) ?? fallback;
        double Measure(CrestMeasure measure) => OptionalNumber(value[measure.Name]) ?? measure.Default;
        int Count(CrestMeasure measure) => Integer(value[measure.Name]) ?? (int)measure.Default;
        return new(CrestBackplate.Named(Text(value[Key.Backplate])) ?? CrestBackplate.Shield,
            CrestFieldDivision.Named(Text(value[Key.FieldDivision])) ?? CrestFieldDivision.Plain,
            CrestOrdinary.Named(Text(value[Key.Ordinary])) ?? CrestOrdinary.None,
            CrestTrim.Named(Text(value[Key.Trim])) ?? CrestTrim.None,
            CrestSymbol.Named(Text(value[Key.Symbol])) ?? CrestSymbol.Fallback,
            CrestChargeLayout.Named(Text(value[Key.ChargeLayout])) ?? CrestChargeLayout.Single,
            Index(Key.BackplateColorIndex), Index(Key.SecondaryFieldColorIndex), Index(Key.OrdinaryColorIndex),
            Index(Key.TrimColorIndex), Index(Key.SymbolColorIndex), TolerantText(value[Key.StartingPresetId]),
            Index(Key.EdgeColorIndex, Index(Key.TrimColorIndex)), Palette(value[Key.Palette]),
            value[Key.Charge] is JsonObject charge ? DecodeCharge(charge) : null,
            Measure(CrestMeasure.PlateScale), Measure(CrestMeasure.EdgeWidth), Count(CrestMeasure.DivisionCount),
            CrestFinish.Named(Text(value[Key.Finish])) ?? CrestFinish.Flat,
            Measure(CrestMeasure.OrdinaryWidth), Measure(CrestMeasure.TrimWeight), Count(CrestMeasure.TrimDetail),
            Measure(CrestMeasure.ChargeScale), Measure(CrestMeasure.ChargeOffset),
            CrestChargeWeight.Named(Text(value[Key.ChargeWeight])) ?? CrestChargeWeight.Bold,
            Measure(CrestMeasure.SheenAngle), Count(CrestMeasure.SealTeeth), TolerantFlag(value[Key.ShowsOutline]) ?? false,
            CrestDepth.Named(Text(value[Key.Depth])) ?? CrestDepth.None);
    }

    internal static JsonObject Encode(SpaceCrest crest) {
        var value = new JsonObject {
            [Key.Backplate] = crest.Backplate.Name,
            [Key.FieldDivision] = crest.FieldDivision.Name,
            [Key.Ordinary] = crest.Ordinary.Name,
            [Key.Trim] = crest.Trim.Name,
            [Key.Symbol] = crest.Symbol.Name,
            [Key.ChargeLayout] = crest.ChargeLayout.Name,
            [Key.BackplateColorIndex] = crest.BackplateColorIndex,
            [Key.SecondaryFieldColorIndex] = crest.SecondaryFieldColorIndex,
            [Key.OrdinaryColorIndex] = crest.OrdinaryColorIndex,
            [Key.TrimColorIndex] = crest.TrimColorIndex,
            [Key.SymbolColorIndex] = crest.SymbolColorIndex
        };
        Put(value, Key.StartingPresetId, crest.StartingPresetId);
        value[Key.EdgeColorIndex] = crest.EdgeColorIndex;
        if (crest.Palette is { } palette) value[Key.Palette] = Encode(palette);
        if (crest.Charge is { } charge) value[Key.Charge] = Encode(charge);
        value[CrestMeasure.PlateScale.Name] = crest.PlateScale;
        value[CrestMeasure.EdgeWidth.Name] = crest.EdgeWidth;
        value[CrestMeasure.DivisionCount.Name] = crest.DivisionCount;
        value[Key.Finish] = crest.Finish.Name;
        value[CrestMeasure.OrdinaryWidth.Name] = crest.OrdinaryWidth;
        value[CrestMeasure.TrimWeight.Name] = crest.TrimWeight;
        value[CrestMeasure.TrimDetail.Name] = crest.TrimDetail;
        value[CrestMeasure.ChargeScale.Name] = crest.ChargeScale;
        value[CrestMeasure.ChargeOffset.Name] = crest.ChargeOffset;
        value[Key.ChargeWeight] = crest.ChargeWeight.Name;
        value[CrestMeasure.SheenAngle.Name] = crest.SheenAngle;
        value[CrestMeasure.SealTeeth.Name] = crest.SealTeeth;
        value[Key.ShowsOutline] = crest.ShowsOutline;
        value[Key.Depth] = crest.Depth.Name;
        return value;
    }

    /// A custom figure. An unknown kind draws nothing, a heraldic figure this
    /// build cannot name is the mountain, and a monogram is serif unless it says.
    internal static CrestCharge DecodeCharge(JsonObject value) {
        var text = TolerantText(value[Key.Value]) ?? "";
        var kind = CrestChargeKind.Named(TolerantText(value[Key.Kind])) ?? CrestChargeKind.None;
        return kind.Kind switch {
            CrestChargeKind.Kinds.Heraldic => new(kind, CrestSymbol.Named(text) ?? CrestSymbol.Fallback),
            CrestChargeKind.Kinds.System or CrestChargeKind.Kinds.Emoji => new(kind, Text: text),
            CrestChargeKind.Kinds.Monogram => new(kind, Text: text,
                Style: CrestMonogramStyle.Named(TolerantText(value[Key.Style])) ?? CrestMonogramStyle.Serif),
            _ => new(CrestChargeKind.None)
        };
    }

    internal static JsonObject Encode(CrestCharge charge) {
        var value = new JsonObject { [Key.Kind] = charge.Kind.Name };
        if (charge.Kind == CrestChargeKind.Heraldic && charge.Symbol is { } symbol) value[Key.Value] = symbol.Name;
        else if (charge.Kind != CrestChargeKind.None) value[Key.Value] = charge.Text ?? "";
        if (charge.Kind == CrestChargeKind.Monogram) value[Key.Style] = (charge.Style ?? CrestMonogramStyle.Serif).Name;
        return value;
    }

    private static ColorPalette? Palette(JsonNode? node) =>
        node is JsonArray colors ? new([.. colors.OfType<JsonObject>().Select(DecodeColor)]) : null;

    private static JsonArray Encode(ColorPalette palette) => new(palette.Colors.Select(color => (JsonNode?)Encode(color)).ToArray());

    #endregion
}
