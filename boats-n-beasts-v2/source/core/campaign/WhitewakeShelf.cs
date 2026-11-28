using static BoatsNBeasts.Core.SeaDuty;

namespace BoatsNBeasts.Core;

public static partial class FarLedger
{
    static CampaignArc Whitewake() => CampaignArc.Create("Whitewake Shelf","The Warm Side of the Ice",
        "On the shelf they keep their homes warm by boiling seawater under the ice. The winter mail has started arriving hot. A piece of one of Vara’s letters has been used to plug a steam pipe.",
        "A tin mitten full of polished blue ice",
        new("Anet  /  pipe fitter","Who gets the first thaw?",
            "Opening the hot main will free the trapped mail crews before the next swell. Running it under the infirmary first will keep the medicine from freezing. Anet hands you the valve wheel.",
            "Thaw the mail crews","Warm the infirmary",
            "The postmaster tears his mailbag into bandages and asks for a berth on the medicine run.",
            "The infirmary empties its blankets into sledges. Fever patients ring their mugs against the rail until the sledges reach the post boat."),
        4,
        [
            Order("ice-post",Salvage,"Letters by the Pound","The registry recycles undelivered post as pipe wadding. The mail boat is embedded in the ice with half its cargo still dry.",
                "Recover the mail bags from the thermal leads.","Tallow Seal","Vara finds one of her own letters. Oren has answered on the envelope and put it back in the same bag.",6),
            Order("ice-lung",Landing,"Steam Lung","A giant walrus sleeps over the warm valve. Someone has riveted boiler plates to its back. Each breath raises the pressure beneath the infirmary.",
                "Unseat the boiler plates and free the hot main.","Stoveback Walrus","The walrus slides off under its own steam. Nell, who has been saving that line all day, finally gets to use it.",6),
            Order("ice-sled",Convoy,"The Sled Post","With their boat freed, the mail crews turn their hull upside down and pull it as a sledge over the outer floes.",
                "Escort the mail sledge across the broken shelf.","Brine Sledge","The postmaster gives Vara a return stamp. She addresses a blank postcard to her brother and keeps it in her pocket.",6),
            Order("ice-cook",Landing,"A Kitchen for Giants","Pip’s mother Jo cooked aboard a registry survey ship. Her recipes are carved into the pantry ice, measured in buckets. One includes the ship’s next appointment.",
                "Reach the cold pantry and take a rubbing of Jo’s supper list.","Freezer Dog","Pip’s favorite meal is on the back of the list. Oren and Jo had planned to meet at Tangleloom.",7),
            Order("ice-fee",Hunt,"The Boat That Skated","A runner skates between floes on iron ribs, collecting a heating fee from each settlement. Its drum contains a ledger of clinic fuel diverted south.",
                "Overtake the runner and recover the medicine allotments.","The Sliding Scale","The infirmary keeps its steam until morning. Anet bolts the spare wheel above your own galley stove.",6),
            Order("ice-lights",Sounding,"Red Buoys Under Ice","Oren walked out here with a red buoy under each arm. No one saw him come back. Find where he let them go and you will find his route.",
                "Read the submerged buoys and chart the warm passage to Tangleloom.","Icewick Narwhal","Two bright points rise behind the ship. Someone farther south is still tending Oren’s line.",7)
        ],
        Order("ice-tonic",Blockade,"The Medicine Shelf","The inspection schooner has barred the mouth of the warm lead and impounded the clinic’s last crate of bitter tonic.",
            "Break the schooner’s ice line and return the tonic.","Fever Buoy","Anet measures out a tablespoon for every child. She gives Lio two because he makes such a fine face.",6));
}
