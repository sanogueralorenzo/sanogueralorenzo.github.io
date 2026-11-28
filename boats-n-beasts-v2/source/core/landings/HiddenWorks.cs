using System.Numerics;

namespace BoatsNBeasts.Core;

public enum InnerWork { Casting, Floodgate, Counterpoise, Loom }
public enum WorksStage { Mouth, Transfer, Sentries, Archive, TwoHands, KeyRoom, Stairs }
public sealed record HiddenWorks(string Title, string SafeRoom, string RiskRoom, string Archive, string Key, string Apparatus,
    string Entry, string Discovery, string Exit, InnerWork Mechanism)
{
    public static HiddenWorks? For(CampaignOrder order)
    {
        if (order.Island.Length == 0 || !order.Ashore) return null;
        var arc = FarLedger.Arcs.FirstOrDefault(a => a.Region == order.Region);
        var first = arc?.Islands.FirstOrDefault()?.Outings.FirstOrDefault(o => o.Ashore);
        return first?.Id == order.Id ? Regional(order.Region) : null;
    }
    (string Room, string Relic, string Note)? memory;
    static HiddenWorks? Regional(string region) => region switch
    {
        "Cinder Narrows" => new("The Upturned Dock", "Hull lift", "Tar pit", "Dita’s loft", "keel key", "rowlock press",
            "Dita’s grandfather drove the first keel in from below. Lio finds the handline he used to climb out.",
            "Two pencil outlines meet on the ceiling. Dita was seven when she traced her palm inside her grandfather’s. Both hands have to steady a reversible keel.",
            "The rowlock press lets go. Dita can feel the dry dock turn gently under her feet.", InnerWork.Casting),
        "Reedglass Delta" => new("The School Below the Sluice", "Chalk stair", "Ink sump", "Classroom", "drawer key", "school sluice",
            "Eda turns the bottom step upside down. A fish skeleton in a jar marks the entrance to the last classroom above flood level.",
            "Under the teacher’s desk are nine peg holes and ten names. Eda had walked the tenth child over the border before roll call every morning.",
            "The sluice coughs up a brass drawer key. Eda puts it inside the attendance book.", InnerWork.Floodgate),
        "Hanging Orchard" => new("The Graft Galleries", "Nurse lift", "Pruning chute", "Growth rings", "graft wedge", "crown balance",
            "The oldest graft has swallowed the stairs. Hennel points out where the roots have grown around a little service lift.",
            "A row of marks records the twins’ height on opposite faces of one branch. A band of cloth joins the last two measurements.",
            "The counterpoise settles. Two shoots lean away from each other without cracking the trunk.", InnerWork.Counterpoise),
        "Whitewake Shelf" => new("The Onion House", "Blanket hoist", "Steam scar", "Potting shed", "cellar key", "stove shoe",
            "Mittens are drying on an iron rung under the floor. The crew follows their warm drips down to the first lamp.",
            "Each onion bed has a tin lid for a nameplate. Tavi recognizes the thumb dent his mother made when she first lifted the night route.",
            "The shoe seats in the stove. Thirteen little green shadows appear on the cellar ceiling.", InnerWork.Casting),
        "Tangleloom Sound" => new("The Inside Catch", "Spool lift", "Needle trench", "Pattern room", "half-button", "two-sided clasp",
            "The night shift marked its way home with buttons sewn into the plaster. Sib finds the first one under her thumbnail.",
            "The oldest pattern shows two open hands on opposite sides of the same door. A worker crossed out the drawing of a key and stitched a sleeve over it.",
            "The clasp opens in two directions. Sib holds a hand out to somebody she has only seen in silhouette.", InnerWork.Loom),
        "Choir Deep" => new("The Air Behind the Ward", "Linen cradle", "Breath sump", "Night desk", "vent key", "lung valve",
            "Reva keeps a clean strip of cotton at every bend in the duct. Follow the strips that still move, she tells the crew.",
            "The night log takes a whole page to describe one patient squeezing Reva’s hand. Her reply is written as a slight correction to the air pressure.",
            "The vent opens. In the ward above, a strip of linen lifts as though someone had taken a breath.", InnerWork.Floodgate),
        "Sable Court" => new("The Hall of Second Crossings", "Evidence lift", "Mirror drain", "Fare counter", "witness key", "counterweight",
            "Ada’s reflection reaches the turnstile just after she does. The second click has been collecting a fare for twenty years.",
            "Ada’s husband drew his ferry on a scrap of mirror backing. Under the boat is a seated figure with one hand tucked round a halfpenny.",
            "The counterweight comes down once. Ada counts only one return on the dial.", InnerWork.Counterpoise),
        "The Unnumbered Sea" => new("The Lost Interval", "Minute lift", "Escapement pit", "Pantry ledger", "pantry spring", "double escapement",
            "Hester has been keeping the lost hour in a pantry with a wire screen. Something inside has been eating the hands off her clocks.",
            "Jo’s name is written at four different heights on the birthday shelf. Hester gave her a little more reach every time she came back hungry.",
            "Two hands meet at noon. The door opens onto a minute Hester thought she had thrown away.", InnerWork.Loom),
        "The Saltstep Terraces" => new("The Jar Under the Stairs", "Cucumber lift", "Brine sump", "Anja’s pantry", "salt key", "night sluice",
            "A pickle has rolled downhill against the tide. Anja follows the little bubbles to the service door under the pantry.",
            "Seven different thumbprints dent one recipe card. Anja’s grandmother learned to make the brine from everybody whose kitchen the reef had borrowed.",
            "The card dries in a warm spoon. Anja can lift the fork before the little reef has to take another step.", InnerWork.Floodgate)
        { memory = ("Cold cupboard", "red fork sleeve", "The sleeve is lined with tiny pockets. Every family that lent a kitchen tucked in a single dill seed.") },
        "Bottlebrush Reach" => new("The Room That Cooled First", "Firebrick hoist", "Glass culvert", "Drawing shelf", "annealer’s peg", "cooling press",
            "Rim catches a rolling tumbler before it falls through a crack in the raft. A smaller tumbler answers from underneath.",
            "The workshop plans show a narrow pillow of brick under every glass. Her father once slept beside the first kiln in case the floors cooled unevenly.",
            "The press opens square. A glass on its side stays where Rim sets it, for the first time in her apprenticeship.", InnerWork.Casting)
        { memory = ("Pillow shelf", "bottomless cup", "Rim turns the broken cup upside down. Her father marked his first week of work on its base.") },
        "Waxwing Roads" => new("The Shelf After Lights Out", "Wick lift", "Sulfur trench", "Roster room", "bunk catch", "wing balance",
            "Yali ducks under the flight shelf to count the pinpricks of light. Eight little air holes shine through seven matchboxes.",
            "Kest’s first roster scratch is a small triangle drawn under a number. Yali remembers leaving the unsteady bird a place beside the stove.",
            "The extra drawer shifts into line. Yali can carry the spark and keep seven sleeping birds out of the rain.", InnerWork.Counterpoise)
        { memory = ("Wick cupboard", "practice feather", "The old feather is too big for a bird. Yali held it in her own teeth to show a stubborn fledgling how to balance.") },
        "The Sleeping Narrows" => new("Below the Laundry Manger", "Blanket sling", "Soap race", "Mending table", "linen hook", "pinning frame",
            "Fen pokes her head through a white sheet and meets her own laundry mark printed on the underside of a sleeping fin.",
            "A note stitched inside the sheet asks whoever changes this bed next to leave room for one more. Three different laundresses have added a stitch.",
            "A slot opens above the manger. Fen can lift the bedding without asking the island to wake.", InnerWork.Loom)
        { memory = ("Blue cupboard", "linen fish", "A child twisted a scrap of clean sheet into a fish for the laundress on the night shift. Fen has kept it through every wash.") },
        "Tinmoon Anchorage" => new("The House Inside the Bolt", "Keywheel lift", "Tide cellar", "Bo’s key rack", "double tongue", "moon cylinder",
            "Bo has turned his key so often that the street beneath the lock has acquired a keyhole of its own.",
            "A tiny pattern for a second house key is tucked behind a shopping list. Bo’s wife drew it before he ever thought to ask who else should come and go.",
            "The two parts of the tongue move independently. Bo can keep his promise while opening the door.", InnerWork.Casting)
        { memory = ("Coat recess", "ribbon spool", "The last stretch of ribbon has been tied and untied until it shines. Bo knows the fingers that worked it soft.") },
        "Drumskin Gulf" => new("The Quiet Below the Hoop", "Pantry hoist", "Kettle drop", "Old supper board", "hoop catch", "house balance",
            "The wedding house knocks once beneath the floor whenever its skin tightens. Em carries a second plate downstairs.",
            "Two kettle rings overlap on an old board. One wife packed the big kettle and the other packed the little one. They have each been making room for the other ever since.",
            "The ratchet eases the old hoop without tearing it. Em sets down the second plate and sends word to the grocer’s boat.", InnerWork.Counterpoise)
        { memory = ("Linen press", "pear spoon", "A pear stone is sewn into the spoon’s cloth roll. Em and her wife have been carrying a cutting of their first garden.") },
        "Pitchwake Strait" => new("The Cellar of the Last Garden", "Rope cradle", "Tar flume", "Seed drawers", "garden dog", "pitch seam",
            "Dedel smells marigolds in a cellar that ought to hold nothing but hot tar. An old delivery passage ends under the rope walk.",
            "A dead gardener wrote instructions on the back of a coil label. A square yard of ground could travel if the old roots were bound loosely enough.",
            "The seam parts. Roots breathe through the old rope dressing and Dedel takes a slow, delighted breath with them.", InnerWork.Loom)
        { memory = ("Dry seed box", "garden tally", "Every mark is one square foot of earth. Dedel can still put his finger on the little bed where he pulled his first radish.") },
        "The Calving Sea" => new("The Kitchen Beneath the Turnips", "Hamper lift", "Worm gutter", "Wem’s seed rack", "water tooth", "root sluice",
            "The smallest reef is nibbling the warmth out of Wem’s kitchen flags. A new root reaches down between two stones.",
            "A little table has been set under the floor for the white worms. Wem’s youngest child has been feeding them all winter and the calves have followed them home.",
            "Clean water runs between the beds. Wem offers the nursery a turnip only after each calf has cleared the gate.", InnerWork.Floodgate)
        { memory = ("Seed pocket", "marked bowl", "There are two rings inside the bowl. One marks supper for the family and the other measures how much water a hungry reef drinks.") },
        _ => null
    };

    public (string Room, string Relic, string Note) Alcove => memory ?? (Mechanism switch
    {
        InnerWork.Casting when Key == "keel key" => ("Caulker’s berth", "palm mould", "Inside the mould, one small thumb overlaps a carpenter’s broken finger. Dita keeps the impression wrapped in her apron."),
        InnerWork.Casting => ("Coat room", "blue mitten", "An onion seed rattles inside the blue mitten. Tavi checks the thumb before he puts it on."),
        InnerWork.Floodgate when Key == "drawer key" => ("Specimen cupboard", "tenth name peg", "On the back of the missing peg a child has drawn her teacher as a very tall fish."),
        InnerWork.Floodgate => ("Nurse’s bunk", "breath book", "Reva rubs a blue thumbprint on the cover. Her patient turned the pages by blowing on them."),
        InnerWork.Counterpoise when Key == "graft wedge" => ("Nursery nook", "twin grafting knife", "Both blades fold into a single fruitwood handle. Two sets of initials have grown darker with use."),
        InnerWork.Counterpoise => ("Change booth", "fare mirror", "Ada turns the mirror over. The little ferry painted on the back is still carrying its one passenger."),
        InnerWork.Loom when Key == "half-button" => ("Hem chest", "button sampler", "Every shirt on the sampler has its sleeves linked to the next one. Sib recognizes her own crooked stitches."),
        _ => ("Birthday shelf", "clockwork candle", "Someone engraved Jo’s name under a candle built to burn a different color each year.")
    });
    public string[] RoomNames => ["Landing", SafeRoom, RiskRoom, "Upper stair", Archive, "Vara’s drum", "Lio’s bracket", "Transfer lift", Apparatus, Alcove.Room];
    public static (Vector4[] Positions, (int A, int B)[] Edges) Chambers(IslandClimate climate)
    {
        Vector2[] rooms = climate switch
        {
            IslandClimate.Kiln or IslandClimate.Pitchwake => [new(0, 12), new(-9, 7), new(9, 6), new(6, -28), new(0, -3), new(8, -12), new(-8, -10), new(-12, -2), new(2, -20)],
            IslandClimate.Delta or IslandClimate.Saltstep => [new(-10, 10), new(-15, 1), new(-1, 10), new(13, -15), new(-2, -1), new(6, 1), new(-7, -11), new(-16, -8), new(5, -13)],
            IslandClimate.Orchard or IslandClimate.Waxwing => [new(-2, 14), new(-12, 10), new(7, 8), new(-9, -25), new(-2, -2), new(7, -10), new(-13, -9), new(-14, 0), new(-2, -18)],
            IslandClimate.Shelf or IslandClimate.Tinmoon => [new(1, 13), new(-9, 11), new(9, 5), new(2, -28), new(0, -4), new(9, -12), new(-10, -10), new(-13, 1), new(1, -19)],
            IslandClimate.Loom or IslandClimate.Narrows => [new(-14, 7), new(-17, -3), new(-4, 8), new(18, -19), new(-3, -3), new(7, -3), new(-7, -14), new(-13, -12), new(8, -15)],
            IslandClimate.Reef or IslandClimate.Calving => [new(8, 12), new(-3, 13), new(14, 2), new(2, -26), new(4, -3), new(12, -11), new(-5, -9), new(-9, 2), new(3, -18)],
            IslandClimate.Court or IslandClimate.Bottlebrush => [new(-10, 12), new(-18, 5), new(0, 10), new(13, -18), new(-5, -2), new(5, -2), new(-9, -12), new(-17, -5), new(4, -14)],
            _ => [new(0, 16), new(-10, 10), new(10, 10), new(-2, -27), new(0, -2), new(10, -9), new(-11, -9), new(-13, 0), new(0, -18)]
        };
        var spur = (rooms[2] + rooms[5]) * .5f; rooms = [.. rooms, spur + Vector2.Normalize(spur - rooms[4]) * 6.4f];
        Vector4[] places = rooms.Select((p, i) => new Vector4(p.X, p.Y, i == 3 ? 4.1f : i == 8 ? 3.78f : 3.15f, i == 8 ? 3.05f : 2.65f)).ToArray();
        return (places, [(0, 1), (0, 2), (1, 7), (7, 4), (2, 4), (4, 5), (4, 6), (5, 8), (6, 8), (8, 3), (2, 9), (9, 5)]);
    }
}
