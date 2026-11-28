using static BoatsNBeasts.Core.SeaDuty;

namespace BoatsNBeasts.Core;

public static partial class FarLedger
{
    static CampaignArc Unnumbered() => CampaignArc.Create("The Unnumbered Sea","A Port of Your Own",
        "The final page hangs inside an engine that moves harbor lights to match the official chart. Gauge thinks she can stop ships wrecking by making the sea simpler. The three skiffs at Last Light sailed into the gap she left.",
        "The loose needle of the common compass",
        new("Meret Gauge  /  examiner","What belongs on the last page?",
            "Gauge lost her first crew looking for a harbor marked in the wrong place. She built the register so it would never happen again. Pip offers her a pencil. Nell offers her an eraser.",
            "Write the missing names","Leave room for new harbors",
            "Gauge writes the first name in tiny letters. Nell turns the page sideways. There is more room than anyone expected.",
            "Gauge rubs at the page until her fingers are black. Pip draws a little cup in the margin to show where visitors can get tea."),
        8,
        [
            Order("north-tow",Convoy,"A Fleet of Small Things","From every harbor comes something small enough to carry aboard: a whistle, a pear, a mitten, a scrap of canvas. Between them they mark a course the examiner has never sailed.",
                "Carry the harbor pilots along the last uncharted reach.","Compass Petrel","The fleet finds its way by a hundred ordinary sounds. Anet’s tin mitten makes the worst one.",8),
            Order("north-hart",Landing,"The Island Under the Needle","The compass engine is planted on a walking island. The Northless Hart carries the survey platform in its antlers; its own shadow is the last piece of unmapped land.",
                "Free the platform from the Hart and let the walking island stop.","Northless Hart","Gauge steps off the platform looking very small. Vara seats her at the crew table before anyone can put her in irons.",8),
            Order("north-index",Salvage,"An Index of Arrivals","Each missing name needs one mark made by someone who knew the place. The marks are scattered through the survey wrecks at the ends of the compass points.",
                "Gather the harbor marks and deliver the signed index.","The Margin Fish","Oren signs for the hospital. Pip signs for the kitchen. Lio signs for a beach where he had a particularly good nap.",8),
            Order("north-axle",Landing,"A Lever Long Enough","The machine is moving the lamps again. Every harbor crew has brought a tool. Nobody brought a lever long enough, until the kiln pilots lay their boats end to end.",
                "Release the lamp counterweights and open the engine floor.","The Plumb Serpent","The lamps go out for one long breath. Then windows begin to light along a coastline that looks nothing like the official chart.",8),
            Order("north-wake",Blockade,"All Lamps Home","The engine’s last guardship is hauling loose harbor lamps toward the deep. One flame aboard it still belongs to the children of Last Light.",
                "Break the guardship’s tow and recover the home lamp.","The Closed Account","The lamp is dented. Pip points out that this will make it easier to recognize.",8),
            Order("north-return",Convoy,"The Long Way Back","Every boat in the fleet could sail home alone. They decide to take the longest route, calling at every port that brought them this far.",
                "Bring the common compass and its fleet into Last Light Quay.","The Last Headwind","In the galley the stew has stuck to the bottom of the pot. Jo calls it a crust. Vara rings everyone in.",8)
        ],
        Order("north-white",Sounding,"White Space","Without the register the fleet needs a way to mark hazards without claiming the shore. The pilots agree to leave the safe bearings tied to floating lines.",
            "Lay the first public bearings through the unnumbered reach.","The Loose Meridian","At the end of the line someone hangs a spare pencil. The tide moves it enough to write one crooked wave.",8));
}
