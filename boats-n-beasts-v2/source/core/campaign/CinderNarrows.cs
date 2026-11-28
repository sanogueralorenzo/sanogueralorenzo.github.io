using static BoatsNBeasts.Core.SeaDuty;

namespace BoatsNBeasts.Core;

public static partial class FarLedger
{
    static CampaignArc Cinder() => CampaignArc.Create("Cinder Narrows","The Kiln Fleet",
        "The third skiff carried a fired-clay saucer with three thumbprints in it. Nell recognizes the receipt. A whole flotilla of ferries has been impounded as crockery.",
        "A clay ferry small enough to float in a soup bowl",
        new("Sima Redthumb  /  ferry pilot","Whose hands go on the manifest?",
            "Sima puts two manifests on the table. The pilots can take the ferries out under their own seal. The potters could claim the boats as unfired clay and pass the registry ships unharmed. Both crews reach for the ink.",
            "Fly the pilots’ seal","Carry the potters’ mark",
            "Six black handprints dry on a new ensign. The pilots mean to cross the registry line in daylight.",
            "The potters press their marks under the gunwales, where a boarding clerk must kneel to see them."),
        1,
        [
            Order("cinder-pilot",Convoy,"Three Boats of Clay","The little vessels behind Sima’s tug sit so low that waves break into the firing cups. She knows each boat by the note it makes against her hull.",
                "Pilot the unfired ferries through the narrows to the cool slips.","Coalbiter","Sima sets a cup on the dock. It has a hull, four benches and an argument about who gets to be captain.",4),
            Order("cinder-kiln",Landing,"The Breathing Kiln","At low water the slipway tilts upright. The Draft Ox walks inside the firing drum with the kiln keys soldered to its yoke. The ferry crews are still chained below.",
                "Recover the kiln keys and open the cool slips.","Draft Ox","The Ox lies down in a trough of damp sand. Three hulls slide into the water. A woman in a soot apron asks Nell for the registry book.",4),
            Order("cinder-pilots",Blockade,"Hands Above Deck","Sima’s fleet approaches with every pilot standing at the bow. The registry tender drops its examination chain across the throat of the strait.",
                "Take the pilots’ convoy across the examination line.","Chain Gannet","On the far side Sima writes the time of crossing in letters tall enough to read from the tollhouse.",5),
            Order("cinder-ashroom",Landing,"Names Under the Glaze","A potter fired her wage slips into the backs of tiles. The tariff boards nailed those tiles face-in on the walls of a counting house.",
                "Open the ashroom and bring its tiled register back to Nell.","Stamp Beetle","Under the glaze are signatures of ferrymen, cooks and sailmakers. Vara puts her thumb on one of them. Oren. Her brother was here.",5),
            Order("cinder-hulk",Salvage,"The Second Firing","Oren shipped out on a kiln barge. Its furnace fell through the bottom years ago, but the dispatch box will be sitting on the iron fire grate.",
                "Raise the dispatch box from the fire barge and deliver it dry.","Gratejaw","There is no letter inside. There is a careful drawing of the tide wheels at Reedglass and a charcoal handprint with six fingers.",5),
            Order("cinder-float",Convoy,"Launch Day","The registry leaves the lift gates locked and sails out on the tide. Every citizen of the slips climbs aboard a ferry with a ladle, saucepan or ladle-shaped dog.",
                "Bring the kiln fleet through the abandoned gates.","The Gate Tender","At Last Light a girl launches the first clay ferry in a bowl of broth. It holds water on the outside and gravy on the inside. Sima calls that a successful trial.",5)
        ],
        Order("cinder-potters",Salvage,"Soft Cargo","To pass as unfired ware the ferries need their old raw-cargo tags. The customs shed sank during a shift change, along with the only press that could stamp them.",
            "Recover the tag press and fit the potters’ mark before the crossing.","Iron Spindle","The clerk kneels, reads the marks and waves the ferries through. Sima leaves him the bill for his muddy trousers.",5));
}
