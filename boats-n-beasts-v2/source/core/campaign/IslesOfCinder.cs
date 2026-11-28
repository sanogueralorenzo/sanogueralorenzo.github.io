using static BoatsNBeasts.Core.SeaJob;
using static BoatsNBeasts.Core.YardSite;
using static BoatsNBeasts.Core.LandingAction;

namespace BoatsNBeasts.Core;

public static partial class FarLedger
{
    static IslandStory[] CinderIsles() => [
        Isle("Cinder Narrows",1,"Knucklebone Spit","Dita, ferry carpenter",
            "A young carpenter is trying to launch an upside-down boat. Her grandfather built it to work floodwater both ways up. The registry has condemned it for having its keel on the roof.","Dita’s reversible rowlock",
            Crossing("knuckle-splice",SeaDuty.Salvage,"Two Ends to a Keel","Dita needs the matching rowlock from the wreck of the first boat her grandfather built.","Raise the brass rowlocks from the broken slip.","Saddle Crab","The rowlocks fit. Dita turns the boat over and they still fit.",5,Track,SeaJob.Salvage,Unload),
            Landfall("knuckle-bench","The Roofwright","The keels are full of flood mud and a roof crab has moved into the pump chamber.","Gutterback","The pump catches on its second stroke. Three sleepy crabs come out of the scupper.",5,
                At(Haul,West,"Pump lid","Pull the pump lid clear"),At(LandingAction.Cut,East,"Rotted packing","Cut away the rotted packing"),At(Seat,Crane,"Brass rowlock","Seat Dita’s port rowlock")),
            Crossing("knuckle-roll",SeaDuty.Convoy,"Roll Trial","Dita wants witnesses on both sides of the strait when she rolls the first double-keeler.","Take her pilot boat through the breaking tide.","Bilge Tern","The double-keeler comes up right side up twice. Dita asks the clerk to define right.",6,Tow,DriveOff,SeaJob.Guide),
            Landfall("knuckle-sign","The Other Side of the Sign","The slip’s departure board is nailed upside down too. Dita intends to accept the examiner’s complaint in full.","Nailtooth","The new board reads ARRIVALS on both sides. Dita lends the kiln fleet her first serviceable boat.",5,
                At(Brace,Fallen,"Slipping cradle","Brace the cradle for the trial"),At(Turn,East,"Wharf board","Turn the wharf sign over"),At(LandingAction.Guide,Stairs,"First paying fare","Walk Dita’s first passenger down to the boat"))),
        Isle("Cinder Narrows",1,"Latchkey Bank","Bram, locksmith",
            "A locksmith returns from his weekly swim to find that the whole prison island has drifted out on its chain. His daughter runs the bakery in its basement.","A sugar key that opens a biscuit tin",
            Crossing("latch-trail",SeaDuty.Hunt,"The Escaped Prison","A drifting prison leaves a trail of boot soles and warm bread. Bram insists his daughter’s loaves have a distinctive crumb.","Track the island’s broken mooring.","Crumb Skate","The island has fetched up against the old lock reef. Someone has written OUT OF FLOUR on its watchtower.",5,Track,Bait,DriveOff),
            Landfall("latch-oven","A Key for the Oven","The watchhouse runs its locks from the oven flue. Building up the fire will open the cells, but a soot snake has wrapped itself around the damper.","Soot Adder","The locks spring. Nobody leaves until the bread comes out.",5,
                At(LandingAction.Cut,West,"Seized flue","Cut the flue clamp"),At(Haul,Crane,"Chimney brush","Haul the flue brush through"),At(Turn,East,"Oven damper","Open the damper to free the locks")),
            Crossing("latch-tow",SeaDuty.Convoy,"The Bakery Under Tow","The island weighs too much to tow, so Bram saws off the bakery and floats it on old bread tins.","Guide the kitchen through the slag beds.","Cinder Gull","The tins leak. Everybody bails except Bram’s daughter, who has two trays in the oven.",6,Tow,Sound,SeaJob.Guide),
            Landfall("latch-home","Till the Crust Sings","The quay fathers will recognize the bakery as a public pier if the first oven bell rings in time for the change of watch.","Tin Pigeon","Bram throws his obsolete prison keys into the bread tin. His daughter gives Nell the only key that opens it.",5,
                At(Seat,West,"Stove brick","Set the stove brick in the new hearth"),At(Brace,East,"Baker’s bell","Brace the baker’s bell over the door"),At(Turn,Stairs,"Morning watch","Ring in the morning watch"))),
        Isle("Cinder Narrows",1,"Sister Chimneys","Uli and Una, signal twins",
            "The twins send weather reports in short puffs of smoke. Each chimney has received a different bill for the same cloud.","The twins’ slate with a cloud drawn on each side",
            Crossing("twins-soot",SeaDuty.Sounding,"A Cloud with Two Owners","Una says the wind comes from the east and Uli says the east is currently closed. Both have the official paperwork.","Take bearings on the two halves of the smoke plume.","Soot Kite","The wind is going straight up. The examiner forgot to include up.",5,Sound,Track,Relay),
            Landfall("twins-valve","The Wire in the Flue","Someone has strung a wire between the chimneys and hung customs flags from it. When the wind shifts the whole island is briefly under a red flag.","Flag Eater","The twins recover their weather flags and a surprising quantity of socks.",5,
                At(Haul,West,"Flag wire","Hook the signal wire down"),At(LandingAction.Cut,Crane,"Tarred pennants","Cut the tariff flags free"),At(Brace,East,"Weather vane","Brace the louver for the first report")),
            Crossing("twins-wind",SeaDuty.Blockade,"Smoke Signal School","The pilots need a practice run before trusting the new signal. A registry cutter is running the course in reverse, hoisting every wrong flag.","Clear the cutters from the twins’ signal course.","Countermarch","Six ferries round the shoal together. The last skipper signals THANKS with a saucepan lid.",6,SeaJob.Cut,Sound,Relay),
            Landfall("twins-witness","Weather for Everyone","One chimney must face out to sea and one inland. The twins have never worked more than a shout apart.","Capped Swift","Una’s first independent forecast is rain. Uli hangs the laundry anyway. Both sign the ferry pilots’ chart.",5,
                At(Turn,West,"Inland louver","Turn the inland mouth toward town"),At(Seat,East,"Sea pointer","Seat the sea pointer"),At(LandingAction.Guide,Stairs,"Apprentice signaler","Lead the new signaler to her tower"))),
        Isle("Cinder Narrows",1,"Black Apron Cay","Fen, kiln midwife",
            "Half the island is built on the shell of a living turtle. Fen has recognized the sound of an egg turning in an oven wall.","A warm eggshell cup with a bite out of its rim",
            Crossing("apron-bars",SeaDuty.Salvage,"An Oven That Purrs","Fen can tell which bricks are eggs by holding a warm spoon against them. Her spoon chest went overboard during the pilot strike.","Raise Fen’s tools from the ingot barges.","Knobback Ray","A spoon begins ticking while still in the chest. The eggs are nearly ready.",5,Track,SeaJob.Salvage,Unload),
            Landfall("apron-eggs","Soft Brick","A brick inspector has marked all of the eggs for a second firing. Fen wants the crew to work silently until the nesting turtle hears her voice.","Tileback Turtle","The first hatchling shakes off a red quality-control stamp and bites Lio’s cuff.",6,
                At(Haul,West,"Warm bricks","Hook the loose brick course clear"),At(Brace,East,"Egg cradle","Hold the egg cradle steady"),At(LandingAction.Guide,Stairs,"Nest nurse","Escort Fen below the kiln vent")),
            Crossing("apron-school",SeaDuty.Convoy,"A Fleet in a Bucket","Each turtle needs to smell the open sea before it can swim. Fen’s boat smells of biscuits and is proving altogether too attractive.","Escort the hatchling boat to breaking water.","Bucket Shark","They paddle east in a line, apart from one who follows the biscuit tin.",5,Tow,SeaJob.Guide,Relay),
            Landfall("apron-sand","The First Crawl","The foundry fence crosses the only strip of warm sand. The last hatchling keeps coming back to the same post.","Fence Mole","By dawn there is a track through the sand and a proper gate in the fence. Fen’s pilots volunteer for launch day.",5,
                At(LandingAction.Cut,West,"Boundary wire","Cut the foundry boundary wire"),At(Seat,East,"Sand gate","Set the first hinge on the sand gate"),At(Turn,Stairs,"Low latch","Open the gate at shell height")))
    ];
}
