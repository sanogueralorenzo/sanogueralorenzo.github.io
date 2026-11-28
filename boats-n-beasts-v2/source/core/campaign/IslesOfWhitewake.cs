using static BoatsNBeasts.Core.SeaJob;
using static BoatsNBeasts.Core.YardSite;
using static BoatsNBeasts.Core.LandingAction;

namespace BoatsNBeasts.Core;

public static partial class FarLedger
{
    static IslandStory[] WhitewakeIsles() => [
        Isle("Whitewake Shelf",4,"Mitten Bank","Tavi, hot-water porter",
            "Tavi brings hot water to the upstairs flats in tins lined with old mittens. On the coldest morning of the year thirteen mittens have come back empty and still warm.","A tin thimble with a mitten knitted around it",
            Crossing("mitten-warm",SeaDuty.Sounding,"The Thirteenth Tin","Tavi has counted the tins twice. He puts his sore thumb in the empty place on the rack. There is a small warm draft there.",
                "Trace the warm outfalls beneath the bank.","Kettlesnout","Each pipe leads to a flat that was demolished before Tavi was born. Someone below is still accepting his deliveries.",6,Sound,Track,Relay),
            Landfall("mitten-cellar","The Tenants Below","The old cellar is an ice bubble. Thirteen retired night porters are growing green onions under lamplight. Their tunnel home has frozen shut.",
                "Cupboard Lynx","The oldest porter hands Tavi a scallion in a teacup. He puts it in the pocket where his mother kept the route list.",6,
                At(Haul,West,"Cellar screen","Lift the bent screen off the vent"),At(Brace,East,"Steam jacket","Hold the jacket while Tavi frees the wastecock"),At(LandingAction.Guide,Stairs,"Night porter","Lead the oldest porter out to daylight")),
            Crossing("mitten-onions",SeaDuty.Convoy,"First Greens","Thirteen bowls of onion soup are ready for the flats. Every bowl must be kept level. Vara has volunteered to drink any dangerous surplus.",
                "Keep the soup sledges upright through the tilting leads.","Saucer Skate","One bowl spills. An upstairs tenant lowers a bread heel on a string and mops the lid clean.",6,Tow,SeaJob.Guide,Relieve),
            Landfall("mitten-list","Who Lives Upstairs","The housing clerk wants a floor number for the cellar. Tavi proposes number minus one. Nell offers to draw the stair.",
                "Rent Whisker","The next route list begins downstairs. Tavi gets a mitten with a thumb big enough to fit the scallion.",6,
                At(LandingAction.Cut,East,"Painted boards","Cut the old floor boards clear"),At(Seat,West,"Return pipe","Seat the common return pipe"),At(Turn,Crane,"New register","Enter the downstairs tenants on the route"))),
        Isle("Whitewake Shelf",4,"Whistlepan","Osa, ice musician",
            "Five houses sit around a steaming pan. Each house plays one note by opening its bath plug. Tonight the youngest house is due a solo and no sound comes out.","Osa’s smallest bath plug on a blue ribbon",
            Landfall("whistle-silent","Bath Number Five","Osa presses her cheek to the silent bath. Something on the other side taps back in perfect time.",
                "Steam Grouse","There is a diving bell under the tub. The diver inside has been tapping requests for a week.",6,
                At(Haul,Fallen,"Baffle","Hoist the baffle out of the bath"),At(Turn,West,"Listening pipe","Open Osa’s listening pipe"),At(LandingAction.Cut,East,"Bell sling","Cut the frozen sling from the hatch")),
            Crossing("whistle-fork",SeaDuty.Salvage,"The Note at the Bottom","The diver lost the village tuning fork overboard. Osa says it will still be humming. Lio takes his boots off so he can hear it with his feet.",
                "Recover the submerged tuning fork and bring it to the pan.","Humming Fluke","The fork has a tiny crack. When Osa strikes it there are two notes.",6,Track,SeaJob.Salvage,Unload),
            Crossing("whistle-choir",SeaDuty.Sounding,"A Place for the Sixth","Osa wants the diver to play the second note. The bath pipes cross under the water and one now opens directly into a public teapot.",
                "Map the pipes before the evening boil.","Teakettle Narwhal","The tea shop agrees to join the rehearsal on the condition that everyone buys a bun.",7,Sound,Relay,Track),
            Landfall("whistle-song","Water Music","The registry has padlocked all five bath plugs for excessive noise. Osa lays five buns on the rim. The diver puts down a sixth.",
                "Plug Fox","The first chord rattles six windows. The diver's contribution is two notes long. Everybody knows exactly which two.",6,
                At(Brace,West,"Bass drain","Hold the bass drain against the steam"),At(Seat,East,"Cracked fork","Fit the cracked fork beside the hot pipe"),At(Turn,Crane,"Solo plug","Give the diver the first solo"))),
        Isle("Whitewake Shelf",4,"Gullprint Floe","Meri, school surveyor",
            "Meri teaches children to map moving ice by drawing round their feet. A survey crew has copied the footprints into its chart as a permanent road.","Two boot-shaped brass map pins",
            Crossing("gullprint-road",SeaDuty.Convoy,"The Road That Walks","A supply captain has promised to follow the official road even if it moves. The children are wearing the only accurate maps.",
                "Pilot the supply lugger behind the school sledges.","Mapshoe","The captain arrives with both boots dry. He asks Meri to mark the road back.",6,SeaJob.Guide,Tow,Relay),
            Landfall("gullprint-ink","Blue on White","The survey press is printing tomorrow’s floe positions today. Meri’s youngest pupil recognizes a footprint from the morning he stood on one leg.",
                "Footrule Stoat","Meri holds the metal plate against the light. Half the shore is the print of a mitten.",7,
                At(Haul,West,"Press blanket","Hook the press blanket off the rollers"),At(LandingAction.Cut,East,"Tomorrow’s map","Cut the false chart from the frame"),At(Turn,Crane,"Pupil’s proof","Take a proof of the mitten print")),
            Crossing("gullprint-loop",SeaDuty.Hunt,"A Pair of Circles","Two identical supply flags have appeared on opposite horizons. One belongs to Meri’s school. The other is painted on a survey decoy.",
                "Follow the fresh sledge tracks to the stranded class.","Duplicate Gull","The children have tied their sledges in a circle to make a classroom. Nobody has missed spelling.",7,Track,Bait,DriveOff),
            Landfall("gullprint-school","The Moving Classroom","The old schoolhouse cracks along the dotted line painted through its threshold. The sledges have enough timber for runners.",
                "Ruler Hare","The classroom slides six inches and stays up. Meri moves the map pins to the other side of the door.",6,
                At(Seat,West,"First runner","Seat the runner under the blackboard"),At(Brace,East,"Classroom floor","Brace the floor while the children board"),At(LandingAction.Guide,Stairs,"Last pupil","Help the last pupil out to the runners"))),
        Isle("Whitewake Shelf",4,"Widow’s Kettle","Ren, night ferryman",
            "The kettle above Ren’s stove whistles whenever his wife’s ferry rounds the head. She died five winters ago. Last night the kettle woke the whole bank.","A bent copper whistle carrying two sets of tooth marks",
            Crossing("kettle-answer",SeaDuty.Sounding,"The Second Whistle","Ren has kept the kettle full for five winters. At the headland the water is answering in his wife's three short bursts.",
                "Take soundings at the whistle buoys.","Tinback Diver","One buoy is tied to a child’s ferry ticket punched five winters ago.",7,Sound,Track,Relay),
            Landfall("kettle-boat","The Ticket Window","The ticket office hangs frozen beneath the lip of a cave. A small hand has kept the counter polished.",
                "Cave Badger","A young woman has been maintaining her mother's signal since the crossing closed. Ren had never known she could whistle.",6,
                At(Haul,West,"Ticket grille","Lift the grille clear of the counter"),At(Brace,East,"Cave shutter","Hold the cave shutter open"),At(LandingAction.Guide,Stairs,"Signal keeper","Walk the signal keeper out to Ren")),
            Crossing("kettle-cross",SeaDuty.Blockade,"Crossing Time","Father and daughter plan to run the old ferry once. A registry launch is collecting a reopening charge from everyone who waves from shore.",
                "Break the collection line and escort the family ferry.","Fare Collector","The shore is white with waving handkerchiefs. Ren has to brake because he cannot see.",7,SeaJob.Cut,Relieve,SeaJob.Guide),
            Landfall("kettle-seat","For the Next Hand","The ferry’s whistle is a copper tube that must be bent to fit the teeth of whoever steers. Ren puts both their old whistles on the bench.",
                "Copper Vixen","Their new whistle has two sets of bite marks. The kettle above the stove answers both.",6,
                At(Seat,West,"Copper tube","Seat the copper tube in the ship’s whistle"),At(Haul,Crane,"Bellows line","Run the bellows line through the cabin"),At(Turn,East,"Evening crossing","Sound the first evening crossing")))
    ];
}
