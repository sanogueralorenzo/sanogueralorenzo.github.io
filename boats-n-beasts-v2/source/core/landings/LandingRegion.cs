namespace BoatsNBeasts.Core;

public enum IslandClimate { Kiln, Delta, Orchard, Shelf, Loom, Reef, Court, Stars, Saltstep, Bottlebrush, Waxwing, Narrows, Tinmoon, Drumskin, Pitchwake, Calving }

public sealed record LandingRegion(IslandClimate Climate, string Ground, string Rock, string Trim, string Cloth,
    string[] Districts, string[] Marks, string Cargo, string Lock, string Tally, string Pin, string Castaway)
{
    public string[]? WorkNames { get; init; }
    public static LandingRegion From(string name) => name switch
    {
        "The Saltstep Terraces" => new(IslandClimate.Saltstep, "c3b79a", "796b83", "e8bd84", "6d997d",
            ["Steps of Brine", "Soft Heel", "Tide Nursery", "The Potting Court", "Salt Garden", "Bent Rows"], ["Heel", "Root", "Leaf"], "root cradles", "bed sluices", "gardener’s slate", "grafting wedge", "field botanist")
        { WorkNames = ["Root register", "Seed pool", "Graft bench", "Terrace shelter", "Foot cradle", "Salt lids"] },
        "Bottlebrush Reach" => new(IslandClimate.Bottlebrush, "b0c7a3", "53696e", "eac986", "c96b72",
            ["Glass Root", "Annealer’s Walk", "The Blowpipe", "Brushgrove", "Hot Lip", "Mossbed"], ["Sand", "Glass", "Moss"], "glass specimens", "cooling sluices", "annealer’s ledger", "firebrick", "apprentice annealer")
        { WorkNames = ["Glass index", "Bottle pool", "Annealing bed", "Divers’ shelter", "Blower stand", "Sample cabinet"] },
        "Waxwing Roads" => new(IslandClimate.Waxwing, "c4a381", "795874", "e9bd6b", "bc5357",
            ["Match Hill", "Flight Row", "Airmail Sort", "Underwing", "Ridge Station", "Last Thermal"], ["Wax", "Seal", "Wing"], "courier frames", "wind shutters", "flight card", "wing rib", "courier")
        { WorkNames = ["Flight register", "Wax drift", "Rib bench", "Lee shelter", "Wing drum", "Mail lockers"] },
        "The Sleeping Narrows" => new(IslandClimate.Narrows, "9db7ac", "66627f", "dad4b0", "8090b2",
            ["The Quiet Fin", "Laundry Rise", "Night Ward", "Blanket Stair", "Still Berth", "Resting Teeth"], ["Rest", "Breath", "Fin"], "sleeping slings", "ward vents", "night docket", "bed runner", "night porter")
        { WorkNames = ["Ward rota", "Linen pool", "Bed shoe", "Ward shelter", "Laundry winches", "Quiet cabinets"] },
        "Tinmoon Anchorage" => new(IslandClimate.Tinmoon, "adb8c6", "646479", "ead38f", "668694",
            ["The High Street", "Clock Basin", "The Shoe Pit", "Low Moon Stairs", "Plumbed Yard", "Silver Rill"], ["Half", "Full", "Dark"], "salvage baskets", "tidal hatches", "diver’s manifest", "lead shoe", "salvage diver")
        { WorkNames = ["Moon register", "Salvage nets", "Shoe press", "Diving lock", "Plumb station", "Sunken lockers"] },
        "Drumskin Gulf" => new(IslandClimate.Drumskin, "bc9a82", "746074", "e4c27b", "a65b51",
            ["Hoop Market", "Sound Well", "Rest Mark", "Parcel Floor", "Hollow Lip", "Skinner’s Wharf"], ["Head", "Rim", "Rest"], "reply drums", "skin laces", "public score", "hoop tongue", "drum fitter")
        { WorkNames = ["Public score", "Echo nets", "Hoop bench", "Resting room", "Tuning pegs", "Parcel bench"] },
        "Pitchwake Strait" => new(IslandClimate.Pitchwake, "a18c7b", "4d4d62", "d6ad71", "84605a",
            ["Rosin Wharf", "The Last Garden", "Anchor Dress", "Pitch Flats", "Capstan Ward", "The Drowned Stair"], ["Pitch", "Rope", "Iron"], "dressed anchor lines", "capstan dogs", "mooring roll", "iron rivet", "rope dresser")
        { WorkNames = ["Mooring roll", "Coil berth", "Rivet bed", "Anchor shelter", "Windlass row", "Pitch lockers"] },
        "The Calving Sea" => new(IslandClimate.Calving, "b6c0a9", "737990", "ecc69c", "77a8a0",
            ["Calf Steps", "Warmthumb Pool", "The First Dark", "Nursery Bridge", "Hatching Court", "Soft Foot"], ["Egg", "Foot", "Home"], "reef hammocks", "nursery gates", "hatching log", "nursery shoe", "reef nurse")
        { WorkNames = ["Hatching slate", "Nursery floats", "Cradle bench", "Calf steps", "Hammock drums", "Nursery lids"] },
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
