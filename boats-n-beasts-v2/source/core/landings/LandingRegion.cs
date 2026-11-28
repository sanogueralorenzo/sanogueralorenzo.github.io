namespace BoatsNBeasts.Core;

public enum IslandClimate { Kiln, Delta, Orchard, Shelf, Loom, Reef, Court, Stars }

public sealed record LandingRegion(IslandClimate Climate, string Ground, string Rock, string Trim, string Cloth,
    string[] Districts, string[] Marks, string Cargo, string Lock, string Tally, string Pin, string Castaway)
{
    public static LandingRegion From(string name) => name switch
    {
        "Reedglass Delta" => new(IslandClimate.Delta, "c9af79", "706e64", "a7c984", "567b83",
            ["Silt Index", "Pulp Steps", "The Press Islands", "Rushbinder’s Pool", "Roll Wharf", "Papermill Bend"],
            ["Rush", "Rain", "Reed"], "bundles of reed paper", "mill sluices", "register", "press roller", "paper rigger"),
        "Hanging Orchard" => new(IslandClimate.Orchard, "bf9275", "765668", "f2be54", "ae6888",
            ["Windfall Quay", "Lamp Rows", "Bee-Tender’s Loft", "Crown Nursery", "Pollen Walk", "Fruit Loft"],
            ["Seed", "Leaf", "Bloom"], "fruit lanterns", "orchard cages", "grafting book", "grafting pin", "lamp tender"),
        "Whitewake Shelf" => new(IslandClimate.Shelf, "c9d7d5", "77738a", "efad79", "568eaa",
            ["Thawmarket", "Steam Steps", "Tallow Strand", "Hotwell Yards", "Brine Pans", "Coaling Pool"],
            ["Ice", "Coal", "Steam"], "winter stoveboats", "frost locks", "winter stores", "stove brick", "stokers’ cook"),
        "Tangleloom Sound" => new(IslandClimate.Loom, "baac94", "6d5a76", "edac75", "b9536e",
            ["Bobbin Moor", "Warp Street", "Shuttle House", "The Great Hem", "Spindle Wharf", "Dyewell"],
            ["Warp", "Weft", "Hem"], "bolts of sailcloth", "warp pins", "sailmakers’ docket", "shuttle", "loom hand"),
        "Choir Deep" => new(IslandClimate.Reef, "c9b8ae", "6e688e", "eab68d", "6fbeb6",
            ["Quiet Teeth", "Overtone Shells", "Breath Pool", "The Resonator", "Shell Choir", "Murmur Court"],
            ["Low", "Middle", "High"], "resonator shells", "choir shutters", "score", "tuning shell", "reef singer"),
        "Sable Court" => new(IslandClimate.Court, "9b9392", "524b65", "e0b87a", "865279",
            ["Docket Stair", "Bailiffs’ Yard", "Petition Quay", "Public Bench", "Seal House", "Witness Wharf"],
            ["Word", "Witness", "Seal"], "witness boats", "court chains", "docket", "seal die", "witness"),
        "The Unnumbered Sea" => new(IslandClimate.Stars, "9d99a5", "555776", "ddd391", "68789e",
            ["Bearing Zero", "The Bent Needle", "Starless Walk", "First Meridian", "West of West", "The Lost Point"],
            ["West", "Star", "Home"], "pilots’ skiffs", "meridian chains", "star chart", "compass stone", "lost pilot"),
        _ => new(IslandClimate.Kiln, "928387", "4b4558", "eeb166", "b6604f",
            ["Pumice Slips", "The Drying Racks", "Ash Cartway", "The Breathing Kiln", "Coal Bight", "The Last Chimney"],
            ["Flame", "Brick", "Hull"], "hollow clay ferries", "kiln chains", "firing ledger", "kiln pin", "ferry potter")
    };
}
