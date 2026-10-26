namespace CrestCore.Contracts;

/// The accent a Space shows in places too small for its branding: the system
/// color it tints small marks with, the house look a new Space of the accent
/// wears, and the look a Space stored before branding existed wears.
///
/// The stored session and synced Space records spell an accent as its `Name`,
/// so a name never changes. An accent travels as its index in `All`, so `All`
/// is append-only.
public sealed class SpaceAccent {
    #region Static Variables

    /// Winter.
    public static readonly SpaceAccent Indigo = new(name: "indigo", tint: SystemTint.Indigo,
        legacyColors: [Tincture.Ink, Tincture.Ocean, Tincture.Gold], house: SpaceHouse.Winter.Look, swatch: Tincture.Indigo);
    /// Sun.
    public static readonly SpaceAccent Orange = new(name: "orange", tint: SystemTint.Orange,
        legacyColors: [Tincture.Ember, Tincture.Gold, Tincture.Ocean], house: SpaceHouse.Sun.Look, swatch: Tincture.Ember);
    /// Meadow.
    public static readonly SpaceAccent Teal = new(name: "teal", tint: SystemTint.Teal,
        legacyColors: [Tincture.Teal, Tincture.Ocean, Tincture.Sand], house: SpaceHouse.Meadow.Look, swatch: Tincture.Teal);
    /// Lion.
    public static readonly SpaceAccent Rose = new(name: "rose", tint: SystemTint.Pink,
        legacyColors: [Tincture.Rose, Tincture.Indigo, Tincture.Sand], house: SpaceHouse.Lion.Look, swatch: Tincture.Rose);

    public static IReadOnlyList<SpaceAccent> All { get; } = [Indigo, Orange, Teal, Rose];

    #endregion

    #region Variables

    public string Name { get; }

    /// The system color the accent tints small marks with.
    public SystemTint Tint { get; }

    /// The palette a Space stored before branding existed wears: its
    /// background, primary and secondary color.
    public IReadOnlyList<BrandColor> LegacyColors { get; }

    /// The house look a new Space of this accent wears: a deep field, a related
    /// tincture a step above it and one luminous charge, with the crest
    /// composed for it. A Space keeps its copy when this changes.
    public SpaceBranding House { get; }

    /// The one color that stands for the accent, which a color from elsewhere,
    /// such as another browser's Space, is matched against.
    public BrandColor Swatch { get; }

    #endregion

    #region Constructors

    private SpaceAccent(string name, SystemTint tint, IReadOnlyList<Tincture> legacyColors, SpaceBranding house, Tincture swatch) {
        Name = name;
        Tint = tint;
        LegacyColors = [.. legacyColors.Select(tincture => tincture.Color)];
        House = house;
        Swatch = swatch.Color;
    }

    #endregion

    #region Actions - Lookup

    public static SpaceAccent? Named(string? name) => All.FirstOrDefault(accent => accent.Name == name);

    /// The accent whose swatch lies nearest `color` in red, green and blue,
    /// the first in `All` on a tie.
    public static SpaceAccent Nearest(BrandColor color) {
        ArgumentNullException.ThrowIfNull(color);
        return All.MinBy(accent => Math.Pow(color.Red - accent.Swatch.Red, 2) + Math.Pow(color.Green - accent.Swatch.Green, 2)
            + Math.Pow(color.Blue - accent.Swatch.Blue, 2))!;
    }

    #endregion
}
