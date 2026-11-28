using static BoatsNBeasts.Core.SeaDuty;

namespace BoatsNBeasts.Core;

public static partial class FarLedger
{
    static CampaignArc Tangleloom() => CampaignArc.Create("Tangleloom Sound","The Sailmakers’ Strike",
        "Jo booked a mooring under a sail so wide it roofs an entire town. The sail has been cut into squares. Each household has run a different square up a pole.",
        "A patchwork pennant, hemmed in eight different hands",
        new("Jo  /  ship’s cook","How do we mend the roof?",
            "The biggest panel bears the registry seal. Raise it and the inspectors will let the town shelter in its lee. Cut the seal to pieces and every household can sew a square into a sail of its own.",
            "Raise the shared roof","Cut independent sails",
            "The seal goes up upside down. Every child in Tangleloom swears this was a terrible accident.",
            "At dusk a hundred little squares crowd the basin. Jo recognizes each family by its stitching."),
        5,
        [
            Order("loom-wind",Sounding,"A Sound Full of Thread","Great ropes carry wind between the upper mills. Jo sent stew to the loom crews for months, billing it all as sail grease.",
                "Find the leeward approaches to the suspended mills.","Bobbintail","The winchman lowers a cook’s apron. Jo is under the roof with the strikers.",6),
            Order("loom-overcast",Landing,"Overcast Stitch","The town’s master loom is tied into a spider’s web. Pull the wrong warp and every work platform swings. The spider has been feeding paper orders to its young.",
                "Release the master shuttle and get the weavers down.","Shuttle Spider","Jo climbs down last. Pip is safe, she says. Oren took her aboard an unregistered hospital ship to find her father.",6),
            Order("loom-roof",Blockade,"A Flag the Size of a Town","The registry recognizes the upturned seal and sends a cutter to correct the error. A single well-placed tow rope could bring the whole roof down.",
                "Hold the roof moorings and turn away the inspection cutter.","The Hem Ripper","The cutter’s ensign comes off in your hands. Jo hems it into a row of really excellent dishcloths.",7),
            Order("loom-figure",Landing,"A Man Sewn Out of Wind","The tally house pays workers by the turn of a wooden figure’s arms. They have been working twice as fast as the figure for years.",
                "Recover the original turning gear and open the unpaid wage chest.","Tally Jack","The original gear is varnished with sugar. Nell laughs so hard that she has to sit on the chest.",7),
            Order("loom-ferry",Convoy,"Jo’s Last Kitchen","Jo puts her whole kitchen on a barge. She has a morning appointment with a daughter who expects breakfast.",
                "Escort the kitchen barge past the cloth-boiling islands.","Basting Gull","Pip is still out at sea. At the table where she should be, Vara reads aloud from Oren’s envelope.",7),
            Order("loom-song",Hunt,"The Singing Bobbin","Ships navigating Choir Deep carry a tuned wooden bobbin. A spinner dragged Jo’s bobbin overboard and is sewing it through the open water.",
                "Recover the tuned bobbin without losing its pitch.","Warp Eel","When Jo blows across the bobbin, something huge answers from under the harbor floor.",6)
        ],
        Order("loom-fleet",Convoy,"Sails Without Numbers","The harbor master has a hundred blank clearance slips and eight minutes of ink. Outside, the family boats are trying their new sails for the first time.",
            "Shepherd the family fleet out of the loom basin.","The Unpicker","Pip’s patchwork pennant is at the head of the fleet. Jo nearly leaps after it before she sees the patch is a copy.",7));
}
