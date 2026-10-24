namespace CrestCore.Contracts;

/// A named color Crest offers and draws Spaces with: the colors a Space picks
/// from, and the tinctures each house's look is made of.
public sealed class Tincture {
    #region Variables

    public static readonly Tincture Ink = new("ink", "Ink", new(0.08, 0.15, 0.23));
    public static readonly Tincture Indigo = new("indigo", "Indigo", new(0.29, 0.25, 0.58));
    public static readonly Tincture Ocean = new("ocean", "Ocean", new(0.22, 0.42, 0.64));
    public static readonly Tincture Sky = new("sky", "Sky", new(0.35, 0.66, 0.84));
    public static readonly Tincture Teal = new("teal", "Teal", new(0.12, 0.49, 0.52));
    public static readonly Tincture Sage = new("sage", "Sage", new(0.39, 0.56, 0.42));
    public static readonly Tincture Gold = new("gold", "Gold", new(0.88, 0.67, 0.25));
    public static readonly Tincture Ember = new("ember", "Ember", new(0.85, 0.27, 0.20));
    public static readonly Tincture Rose = new("rose", "Rose", new(0.72, 0.25, 0.42));
    public static readonly Tincture Sand = new("sand", "Sand", new(0.82, 0.72, 0.56));
    public static readonly Tincture WinterSlate = new("winterSlate", "Slate", new(0.118, 0.157, 0.200));
    public static readonly Tincture WinterSteel = new("winterSteel", "Steel", new(0.243, 0.306, 0.369));
    public static readonly Tincture WinterIce = new("winterIce", "Ice", new(0.525, 0.678, 0.769));
    public static readonly Tincture LionOxblood = new("lionOxblood", "Oxblood", new(0.235, 0.055, 0.102));
    public static readonly Tincture LionCrimson = new("lionCrimson", "Crimson", new(0.447, 0.125, 0.188));
    public static readonly Tincture LionGold = new("lionGold", "Antique Gold", new(0.788, 0.635, 0.329));
    public static readonly Tincture StormMidnight = new("stormMidnight", "Midnight", new(0.082, 0.094, 0.141));
    public static readonly Tincture StormGunmetal = new("stormGunmetal", "Gunmetal", new(0.192, 0.220, 0.282));
    public static readonly Tincture StormBrass = new("stormBrass", "Brass", new(0.690, 0.561, 0.290));
    public static readonly Tincture DragonChar = new("dragonChar", "Char", new(0.102, 0.063, 0.051));
    public static readonly Tincture DragonBlood = new("dragonBlood", "Blood", new(0.478, 0.118, 0.071));
    public static readonly Tincture DragonScarlet = new("dragonScarlet", "Scarlet", new(0.745, 0.267, 0.220));
    public static readonly Tincture MeadowForest = new("meadowForest", "Forest", new(0.082, 0.137, 0.094));
    public static readonly Tincture MeadowMoss = new("meadowMoss", "Moss", new(0.204, 0.341, 0.220));
    public static readonly Tincture MeadowWheat = new("meadowWheat", "Wheat", new(0.737, 0.655, 0.400));
    public static readonly Tincture IronBlack = new("ironBlack", "Iron", new(0.055, 0.102, 0.110));
    public static readonly Tincture IronPewter = new("ironPewter", "Pewter", new(0.173, 0.227, 0.235));
    public static readonly Tincture IronPatina = new("ironPatina", "Patina", new(0.612, 0.592, 0.506));
    public static readonly Tincture RiverNavy = new("riverNavy", "Navy", new(0.059, 0.118, 0.180));
    public static readonly Tincture RiverLapis = new("riverLapis", "Lapis", new(0.133, 0.282, 0.424));
    public static readonly Tincture RiverRust = new("riverRust", "Rust", new(0.659, 0.361, 0.255));
    public static readonly Tincture SunUmber = new("sunUmber", "Umber", new(0.208, 0.086, 0.043));
    public static readonly Tincture SunTerracotta = new("sunTerracotta", "Terracotta", new(0.545, 0.239, 0.106));
    public static readonly Tincture SunDune = new("sunDune", "Dune", new(0.816, 0.620, 0.396));
    public static readonly Tincture VigilOnyx = new("vigilOnyx", "Onyx", new(0.063, 0.067, 0.071));
    public static readonly Tincture VigilCharcoal = new("vigilCharcoal", "Charcoal", new(0.153, 0.165, 0.180));
    public static readonly Tincture VigilAsh = new("vigilAsh", "Ash", new(0.482, 0.514, 0.549));
    public static readonly Tincture WinterArgent = new("winterArgent", "Argent", new(0.871, 0.894, 0.910));
    public static readonly Tincture WinterWolf = new("winterWolf", "Wolf Grey", new(0.341, 0.384, 0.427));
    public static readonly Tincture LionGules = new("lionGules", "Gules", new(0.596, 0.114, 0.157));
    public static readonly Tincture LionOr = new("lionOr", "Or", new(0.851, 0.682, 0.318));
    public static readonly Tincture StormOr = new("stormOr", "Storm Gold", new(0.835, 0.655, 0.231));
    public static readonly Tincture StormSable = new("stormSable", "Sable", new(0.090, 0.094, 0.106));
    public static readonly Tincture DragonSable = new("dragonSable", "Night", new(0.071, 0.059, 0.063));
    public static readonly Tincture DragonFire = new("dragonFire", "Fire", new(0.749, 0.180, 0.137));
    public static readonly Tincture MeadowVert = new("meadowVert", "Vert", new(0.188, 0.420, 0.231));
    public static readonly Tincture MeadowRose = new("meadowRose", "Rose Gold", new(0.871, 0.729, 0.318));
    public static readonly Tincture IronOr = new("ironOr", "Kraken Gold", new(0.796, 0.651, 0.302));
    public static readonly Tincture RiverAzure = new("riverAzure", "Azure", new(0.176, 0.369, 0.616));
    public static readonly Tincture RiverGules = new("riverGules", "River Red", new(0.643, 0.157, 0.188));
    public static readonly Tincture RiverArgent = new("riverArgent", "Silver", new(0.851, 0.871, 0.894));
    public static readonly Tincture SunTenne = new("sunTenne", "Tenné", new(0.851, 0.467, 0.176));
    public static readonly Tincture SunGules = new("sunGules", "Sunset Red", new(0.722, 0.165, 0.118));
    public static readonly Tincture SunOr = new("sunOr", "Saffron", new(0.894, 0.718, 0.333));
    public static readonly Tincture VigilBone = new("vigilBone", "Bone", new(0.812, 0.820, 0.831));
    public static readonly Tincture NeutralSmoke = new("neutralSmoke", "Smoke", new(0.337, 0.337, 0.337));
    public static readonly Tincture NeutralGray = new("neutralGray", "Gray", new(0.588, 0.588, 0.588));

    public static IReadOnlyList<Tincture> All { get; } = [
        Ink, Indigo, Ocean, Sky, Teal, Sage, Gold, Ember, Rose, Sand, WinterSlate, WinterSteel, WinterIce, LionOxblood,
        LionCrimson, LionGold, StormMidnight, StormGunmetal, StormBrass, DragonChar, DragonBlood, DragonScarlet,
        MeadowForest, MeadowMoss, MeadowWheat, IronBlack, IronPewter, IronPatina, RiverNavy, RiverLapis, RiverRust,
        SunUmber, SunTerracotta, SunDune, VigilOnyx, VigilCharcoal, VigilAsh, WinterArgent, WinterWolf, LionGules, LionOr,
        StormOr, StormSable, DragonSable, DragonFire, MeadowVert, MeadowRose, IronOr, RiverAzure, RiverGules, RiverArgent,
        SunTenne, SunGules, SunOr, VigilBone, NeutralSmoke, NeutralGray
    ];

    public string Name { get; }

    /// The color's name where a person sees it, such as a palette's tooltip.
    [Localized]
    public string Title { get; }

    public BrandColor Color { get; }

    #endregion

    #region Constructors

    private Tincture(string name, string title, BrandColor color) {
        Name = name;
        Title = title;
        Color = color;
    }

    #endregion

    #region Actions - Lookup

    public static Tincture? Named(string? name) => All.FirstOrDefault(tincture => tincture.Name == name);

    /// The tincture that looks like `color`, allowing for rounding.
    public static Tincture? Matching(BrandColor color) {
        ArgumentNullException.ThrowIfNull(color);
        return All.FirstOrDefault(tincture => Math.Abs(tincture.Color.Red - color.Red) < 0.004
            && Math.Abs(tincture.Color.Green - color.Green) < 0.004 && Math.Abs(tincture.Color.Blue - color.Blue) < 0.004);
    }

    #endregion
}
