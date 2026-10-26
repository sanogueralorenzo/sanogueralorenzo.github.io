namespace CrestCore.Contracts;

/// The look setup gives the Spaces it makes: Crest's own banners and layered
/// crests, or a modern gradient and a plain icon. A look travels as its index
/// in `All`, so `All` is append-only.
public sealed class SetupLook {
    #region Types

    /// Each look is offered with a preview of its own, so the page that
    /// offers them switches over the kind.
    public enum Kinds { Heraldic, Modern }

    #endregion

    #region Static Variables

    /// A Space wears a template's banner and its layered crest.
    public static readonly SetupLook Heraldic = new(Kinds.Heraldic, name: "heraldic", title: "Heraldic",
        newSpaceLook: accent => accent.House,
        applying: branding => branding with { ThemeMode = SpaceThemeMode.Banner, IconStyle = SpaceIconStyle.LayeredCrest });

    /// A Space wears a gradient of its colors, from top to bottom, and a
    /// plain icon.
    public static readonly SetupLook Modern = new(Kinds.Modern, name: "modern", title: "Modern",
        newSpaceLook: accent => SpaceBranding.Painted(accent.LegacyColors, SpaceBannerPattern.Diagonal, strength: 1,
            SpaceBranding.LegacyReadabilityFade, SpaceThemeMode.Gradient, ModernGradientAngle, showsTexture: false),
        applying: branding => branding with {
            ThemeMode = SpaceThemeMode.Gradient,
            GradientAngle = ModernGradientAngle,
            IconStyle = SpaceIconStyle.SimpleSymbol
        });

    public static IReadOnlyList<SetupLook> All { get; } = [Heraldic, Modern];

    /// The angle a modern gradient runs at: straight down the sidebar.
    private const double ModernGradientAngle = 90;

    #endregion

    #region Variables

    public Kinds Kind { get; }

    public string Name { get; }

    /// The look's name where a person picks it.
    [Localized]
    public string Title { get; }

    private readonly Func<SpaceAccent, SpaceBranding> newSpaceLook;
    private readonly Func<SpaceBranding, SpaceBranding> applying;

    #endregion

    #region Constructors

    private SetupLook(Kinds kind, string name, string title, Func<SpaceAccent, SpaceBranding> newSpaceLook,
        Func<SpaceBranding, SpaceBranding> applying) {
        Kind = kind;
        Name = name;
        Title = title;
        this.newSpaceLook = newSpaceLook;
        this.applying = applying;
    }

    #endregion

    #region Actions - Lookup

    public static SetupLook? Named(string? name) => All.FirstOrDefault(look => look.Name == name);

    #endregion

    #region Actions - Looks

    /// The look a new Space of `accent` wears.
    public SpaceBranding NewSpaceLook(SpaceAccent accent) {
        ArgumentNullException.ThrowIfNull(accent);
        return newSpaceLook(accent);
    }

    /// `branding` in this look: its sidebar mode and icon style, keeping its
    /// colors and crest, within the ranges every device draws.
    public SpaceBranding Applying(SpaceBranding branding) {
        ArgumentNullException.ThrowIfNull(branding);
        return SpaceBranding.Normalized(applying(branding));
    }

    /// `customization` with its look in this look.
    internal SpaceCustomization Applying(SpaceCustomization customization) {
        ArgumentNullException.ThrowIfNull(customization);
        return customization with { Branding = Applying(customization.Branding) };
    }

    #endregion
}
