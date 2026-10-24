namespace CrestCore.Contracts;

/// A heraldic figure a crest can carry: its bundled artwork when it has any,
/// else the system glyph that draws it.
public sealed class CrestSymbol {
    #region Variables

    // The Beetle draws the ladybug glyph and is named for it; Oak draws Leaf's
    // glyph, so it stays readable but isn't offered.
    public static readonly CrestSymbol Dragon = new("dragon", "Dragon", CrestVocabulary.Studio, "flame.fill", "CrestCharge-dragon");
    public static readonly CrestSymbol Direwolf = new("direwolf", "Direwolf", CrestVocabulary.Studio, "dog.fill", "CrestCharge-direwolf");
    public static readonly CrestSymbol Lion = new("lion", "Lion", CrestVocabulary.Studio, "pawprint.fill", "CrestCharge-lion");
    public static readonly CrestSymbol Stag = new("stag", "Stag", CrestVocabulary.Studio, "leaf.fill", "CrestCharge-stag");
    public static readonly CrestSymbol Raven = new("raven", "Raven", CrestVocabulary.Studio, "bird.fill", "CrestCharge-raven");
    public static readonly CrestSymbol Griffin = new("griffin", "Griffin", CrestVocabulary.Studio, "bird.fill", "CrestCharge-griffin");
    public static readonly CrestSymbol Eagle = new("eagle", "Eagle", CrestVocabulary.Studio, "shield.fill", "CrestCharge-eagle");
    public static readonly CrestSymbol Bear = new("bear", "Bear", CrestVocabulary.Studio, "shield.fill", "CrestCharge-bear");
    public static readonly CrestSymbol Boar = new("boar", "Boar", CrestVocabulary.Studio, "shield.fill", "CrestCharge-boar");
    public static readonly CrestSymbol Fox = new("fox", "Fox", CrestVocabulary.Studio, "shield.fill", "CrestCharge-fox");
    public static readonly CrestSymbol Horse = new("horse", "Horse", CrestVocabulary.Studio, "shield.fill", "CrestCharge-horse");
    public static readonly CrestSymbol Unicorn = new("unicorn", "Unicorn", CrestVocabulary.Studio, "shield.fill", "CrestCharge-unicorn");
    public static readonly CrestSymbol Wyvern = new("wyvern", "Wyvern", CrestVocabulary.Studio, "shield.fill", "CrestCharge-wyvern");
    public static readonly CrestSymbol Hydra = new("hydra", "Hydra", CrestVocabulary.Studio, "shield.fill", "CrestCharge-hydra");
    public static readonly CrestSymbol Serpent = new("serpent", "Serpent", CrestVocabulary.Studio, "shield.fill", "CrestCharge-serpent");
    public static readonly CrestSymbol Kraken = new("kraken", "Kraken", CrestVocabulary.Studio, "shield.fill", "CrestCharge-kraken");
    public static readonly CrestSymbol Seahorse = new("seahorse", "Seahorse", CrestVocabulary.Studio, "shield.fill", "CrestCharge-seahorse");
    public static readonly CrestSymbol Scorpion = new("scorpion", "Scorpion", CrestVocabulary.Studio, "shield.fill", "CrestCharge-scorpion");
    public static readonly CrestSymbol Bat = new("bat", "Bat", CrestVocabulary.Studio, "shield.fill", "CrestCharge-bat");
    public static readonly CrestSymbol Falcon = new("falcon", "Falcon", CrestVocabulary.Studio, "shield.fill", "CrestCharge-falcon");
    public static readonly CrestSymbol Rose = new("rose", "Rose", CrestVocabulary.Studio, "shield.fill", "CrestCharge-rose");
    public static readonly CrestSymbol Lily = new("lily", "Fleur-de-lis", CrestVocabulary.Studio, "shield.fill", "CrestCharge-lily");
    public static readonly CrestSymbol Pine = new("pine", "Pine", CrestVocabulary.Studio, "shield.fill", "CrestCharge-pine");
    public static readonly CrestSymbol Willow = new("willow", "Willow", CrestVocabulary.Studio, "shield.fill", "CrestCharge-willow");
    public static readonly CrestSymbol Swords = new("swords", "Crossed Swords", CrestVocabulary.Studio, "shield.fill", "CrestCharge-swords");
    public static readonly CrestSymbol Axes = new("axes", "Crossed Axes", CrestVocabulary.Studio, "shield.fill", "CrestCharge-axes");
    public static readonly CrestSymbol Sword = new("sword", "Sword", CrestVocabulary.Studio, "shield.fill", "CrestCharge-sword");
    public static readonly CrestSymbol Trident = new("trident", "Trident", CrestVocabulary.Studio, "shield.fill", "CrestCharge-trident");
    public static readonly CrestSymbol Anchor = new("anchor", "Anchor", CrestVocabulary.Studio, "shield.fill", "CrestCharge-anchor");
    public static readonly CrestSymbol Castle = new("castle", "Castle", CrestVocabulary.Studio, "shield.fill", "CrestCharge-castle");
    public static readonly CrestSymbol Scales = new("scales", "Scales", CrestVocabulary.Studio, "shield.fill", "CrestCharge-scales");
    public static readonly CrestSymbol DragonHead = new("dragonHead", "Dragon Head", CrestVocabulary.Studio, "shield.fill", "CrestCharge-dragonHead");
    public static readonly CrestSymbol Hound = new("hound", "Hound", CrestVocabulary.ExpandedCharges, "dog.fill", null);
    public static readonly CrestSymbol Paw = new("paw", "Paw", CrestVocabulary.ExpandedCharges, "pawprint.fill", null);
    public static readonly CrestSymbol Hare = new("hare", "Hare", CrestVocabulary.Baseline, "hare.fill", null);
    public static readonly CrestSymbol Bird = new("bird", "Bird", CrestVocabulary.Baseline, "bird.fill", null);
    public static readonly CrestSymbol Fish = new("fish", "Fish", CrestVocabulary.Baseline, "fish.fill", null);
    public static readonly CrestSymbol Bee = new("bee", "Beetle", CrestVocabulary.Baseline, "ladybug.fill", null);
    public static readonly CrestSymbol Shell = new("shell", "Shell", CrestVocabulary.Baseline, "fossil.shell.fill", null);
    public static readonly CrestSymbol Sun = new("sun", "Sun", CrestVocabulary.Baseline, "sun.max.fill", null);
    public static readonly CrestSymbol RisingSun = new("risingSun", "Rising Sun", CrestVocabulary.ExpandedCharges, "sun.horizon.fill", null);
    public static readonly CrestSymbol Crescent = new("crescent", "Crescent", CrestVocabulary.Baseline, "moon.fill", null);
    public static readonly CrestSymbol Star = new("star", "Star", CrestVocabulary.Baseline, "star.fill", null);
    public static readonly CrestSymbol Sparkles = new("sparkles", "Sparkles", CrestVocabulary.Baseline, "sparkles", null);
    public static readonly CrestSymbol Lightning = new("lightning", "Lightning", CrestVocabulary.Baseline, "bolt.fill", null);
    public static readonly CrestSymbol Flame = new("flame", "Flame", CrestVocabulary.Baseline, "flame.fill", null);
    public static readonly CrestSymbol Snowflake = new("snowflake", "Snowflake", CrestVocabulary.ExpandedCharges, "snowflake", null);
    public static readonly CrestSymbol Drop = new("drop", "Drop", CrestVocabulary.ExpandedCharges, "drop.fill", null);
    public static readonly CrestSymbol Mountain = new("mountain", "Mountain", CrestVocabulary.Baseline, "mountain.2.fill", null);
    public static readonly CrestSymbol Tree = new("tree", "Tree", CrestVocabulary.Baseline, "tree.fill", null);
    public static readonly CrestSymbol Oak = new("oak", "Oak", CrestVocabulary.Baseline, "leaf.fill", null, isOffered: false);
    public static readonly CrestSymbol Leaf = new("leaf", "Leaf", CrestVocabulary.Baseline, "leaf.fill", null);
    public static readonly CrestSymbol Fern = new("fern", "Frond", CrestVocabulary.Baseline, "laurel.leading", null);
    public static readonly CrestSymbol Flower = new("flower", "Flower", CrestVocabulary.ExpandedCharges, "camera.macro", null);
    public static readonly CrestSymbol Waves = new("waves", "Waves", CrestVocabulary.Baseline, "water.waves", null);
    public static readonly CrestSymbol Tower = new("tower", "Tower", CrestVocabulary.Baseline, "building.columns.fill", null);
    public static readonly CrestSymbol Book = new("book", "Book", CrestVocabulary.Baseline, "book.closed.fill", null);
    public static readonly CrestSymbol Key = new("key", "Key", CrestVocabulary.Baseline, "key.fill", null);
    public static readonly CrestSymbol Hammer = new("hammer", "Hammer", CrestVocabulary.Baseline, "hammer.fill", null);
    public static readonly CrestSymbol Compass = new("compass", "Compass", CrestVocabulary.Baseline, "location.north.circle.fill", null);
    public static readonly CrestSymbol Sailboat = new("sailboat", "Sailboat", CrestVocabulary.Baseline, "sailboat.fill", null);
    public static readonly CrestSymbol Crown = new("crown", "Crown", CrestVocabulary.ExpandedCharges, "crown.fill", null);
    public static readonly CrestSymbol Horn = new("horn", "Horn", CrestVocabulary.ExpandedCharges, "horn.fill", null);
    public static readonly CrestSymbol CrossedBanners = new("crossedBanners", "Banners", CrestVocabulary.ExpandedCharges, "flag.2.crossed.fill", null);

    public static IReadOnlyList<CrestSymbol> All { get; } = [
        Dragon, Direwolf, Lion, Stag, Raven, Griffin, Eagle, Bear, Boar, Fox, Horse, Unicorn, Wyvern, Hydra, Serpent,
        Kraken, Seahorse, Scorpion, Bat, Falcon, Rose, Lily, Pine, Willow, Swords, Axes, Sword, Trident, Anchor, Castle,
        Scales, DragonHead, Hound, Paw, Hare, Bird, Fish, Bee, Shell, Sun, RisingSun, Crescent, Star, Sparkles, Lightning,
        Flame, Snowflake, Drop, Mountain, Tree, Oak, Leaf, Fern, Flower, Waves, Tower, Book, Key, Hammer, Compass, Sailboat,
        Crown, Horn, CrossedBanners
    ];

    /// The figure a crest draws when it names none this build can read.
    public static CrestSymbol Fallback => Mountain;

    public string Name { get; }

    /// The figure's name in the gallery.
    [Localized]
    public string Title { get; }

    /// The first vocabulary that draws the figure.
    public CrestVocabulary DrawnSince { get; }

    /// The system glyph that draws the figure where it has no artwork.
    public string SystemImage { get; }

    /// The bundled artwork that draws the figure, if it has any.
    public string? AssetName { get; }

    /// Whether the gallery offers the figure.
    public bool IsOffered { get; }

    #endregion

    #region Constructors

    private CrestSymbol(string name, string title, CrestVocabulary drawnSince, string systemImage, string? assetName,
        bool isOffered = true) {
        Name = name;
        Title = title;
        DrawnSince = drawnSince;
        SystemImage = systemImage;
        AssetName = assetName;
        IsOffered = isOffered;
    }

    #endregion

    #region Actions - Lookup

    public static CrestSymbol? Named(string? name) => All.FirstOrDefault(symbol => symbol.Name == name);

    #endregion
}
