using static BoatsNBeasts.Core.SeaJob;
using static BoatsNBeasts.Core.YardSite;
using static BoatsNBeasts.Core.LandingAction;

namespace BoatsNBeasts.Core;

public static partial class FarLedger
{
    static IslandStory[] SableIsles() => [
        Isle("Sable Court",7,"Halfpenny Steps","Ada, toll widow",
            "Ada has carried the same halfpenny to court every morning for twenty years. Her late husband paid the crossing toll twice on his last journey. She wants the change.","A halfpenny worn thin enough to float on a cup",
            Crossing("halfpenny-trip",SeaDuty.Sounding,"Out and Back","The toll book lists one outbound trip and two returns. Ada knows her husband would have enjoyed the extra return if he had been offered it.",
                "Trace the toll markers that recorded both returns.","Ledger Pike","The middle marker is a signal mirror. It has been billing boats for their reflections.",7,Sound,Track,Relay),
            Landfall("halfpenny-glass","The Fare in the Mirror","Ada sees her husband reflected in the glass. It is the line of his boat painted there in tar, exactly the width of his forefinger.",
                "Silvered Terrier","She lifts the tar outline onto a scrap of sail. Nell enters the husband's real crossing in the margin.",7,
                At(Haul,West,"Mirror frame","Lift the mirror frame off the toll post"),At(LandingAction.Cut,East,"Toll stencil","Cut the tarred stencil away"),At(Turn,Crane,"Crossing book","Correct the crossing book for the real journey")),
            Crossing("halfpenny-box",SeaDuty.Salvage,"The Change Box","The bailiff has approved Ada’s refund. The old change box lies under a pier where a hundred overpaid fares have been glued together by salt.",
                "Raise the change box and bring it to the public landing.","Purse Perch","Ada hears the coins break apart as the box dries. She counts one for every person on the steps.",7,SeaJob.Salvage,Relieve,Unload),
            Landfall("halfpenny-queue","Everyone Behind Her","Ada has been first in line for twenty years. At the window she turns around and begins to take names.",
                "Queue Jackal","She spends her halfpenny on tea for the next widow. The kettle makes enough for both of them.",7,
                At(Seat,West,"Pay window","Seat the change drawer at the public window"),At(Turn,East,"Refund book","Open the refund book to everyone"),At(LandingAction.Guide,Stairs,"Next claimant","Take the next claimant to the window"))),
        Isle("Sable Court",7,"Nine Chairs","Lev, court carpenter",
            "Lev builds a chair for each witness. A case about a vanished crew has nine witnesses and only eight chairs. The missing chair is doing jury service in another court.","A folding stool with nine names under its seat",
            Landfall("chairs-seat","The Eighth Leg","A bailiff has ordered Lev to prove a chair can testify before he will release it from the jury room.",
                "Upholster Beetle","Under the old seat are nine sets of initials. Lev remembers which sailor carved each one while waiting to testify.",7,
                At(LandingAction.Cut,West,"Seat webbing","Open the old webbing under the seat"),At(Haul,East,"Back rail","Lift the rail to expose the initials"),At(Turn,Crane,"Carpenter’s proof","Copy the nine cuts into the record")),
            Crossing("chairs-court",SeaDuty.Hunt,"A Chair Under Sail","The jury court is a raft of desks with the witness chair lashed upside down to its mast. It is sailing away to deliberate.",
                "Intercept the jury raft and recover the ninth chair.","Cushion Skua","The jurors give up the chair as soon as they discover the carpenter can fix their wobbly desk.",7,Track,DriveOff,SeaJob.Salvage),
            Crossing("chairs-nine",SeaDuty.Convoy,"Reserved Seating","Lev has invited the vanished crew’s families to sit in their places. The families insist on carrying the chairs across the sound themselves.",
                "Escort the chair rafts into the public basin.","Footstool Eel","A child falls asleep on the ninth chair. Nobody is willing to wake her at the landing.",8,Tow,SeaJob.Guide,Relieve),
            Landfall("chairs-room","The Empty Place","There are still only eight chairs on the floor. Lev sets the folding stool beside the table for whoever comes home next.",
                "Bench Rook","The stool fits in the space between the judge and the door. For the first time a late witness has somewhere to sit.",7,
                At(Seat,West,"Seat hinge","Seat the folding hinge in Lev’s stool"),At(Turn,East,"Witness roll","Read the nine families into the roll"),At(LandingAction.Guide,Stairs,"Sleeping witness","Carry the sleeping child through the gallery"))),
        Isle("Sable Court",7,"Hush Bell","Edda, interpreter",
            "The bell at Hush Bell makes no sound. Witnesses feel it through the floorboards. The registry has declared the court permanently adjourned because its clerk cannot hear it.","A smooth handbell clapper wrapped in felt",
            Crossing("hush-note",SeaDuty.Sounding,"A Note in the Deck","Edda lays a palm on the mast and tells Lio the current is turning. He tries it with his forehead and discovers a loose nail.",
                "Map the standing wave that carries the summons.","Mute Marlin","The wave passes beneath every dock except the clerk's, which stands on rubber feet.",7,Sound,Track,Relay),
            Landfall("hush-floor","Contact with the Court","The public bench has been sawn apart from the clerk’s dais. Edda asks for a single plank long enough to touch both.",
                "Gavel Moth","The clerk feels the summons through his shoes. He takes one off and hears it again through his hand.",7,
                At(Haul,West,"Sounding plank","Raise the long sounding plank from its rack"),At(Seat,East,"Clerk’s dais","Seat one end beneath the clerk’s chair"),At(Brace,Crane,"Public bench","Brace the other end under the public bench")),
            Crossing("hush-torch",SeaDuty.Blockade,"Public Notice","An examination cutter patrols the old silent approach. Edda's boat carries a lantern with a shutter large enough to sign words across the bay.",
                "Hold open the crossing while Edda signs the hearing notice.","Wick Warden","Boats answer in lights until the clerk's window shines with every color of fish oil.",8,SeaJob.Cut,Relay,DriveOff),
            Landfall("hush-name","The Witness’s Own Hand","Edda has interpreted forty years of testimony. The register has no box for the name of the person speaking through her hands.",
                "Margin Owl","Nell draws a second line on every form. Edda rings court in with her palm flat on the wood.",7,
                At(LandingAction.Cut,West,"Old binding","Cut the narrow forms out of the register"),At(Turn,East,"Speaker’s line","Enter the witness’s own name"),At(LandingAction.Guide,Stairs,"New interpreter","Lead Edda’s apprentice to the sounding plank"))),
        Isle("Sable Court",7,"Black Bread Bar","Mik, prisoner cook",
            "Every loaf baked in the prison has a square corner and a round corner. Mik uses the shapes to remember which prisoners have a home to return to.","A square biscuit in a round tin",
            Crossing("bread-tins",SeaDuty.Salvage,"The Round Tins","The old bread barge went down with a rack of round tins for prisoners due to be released. The prison has been serving square loaves for months.",
                "Raise the round bread tins from the drowned bakery.","Tin Skate","One tin is dented in the shape of a front door. Mik recognizes the house.",7,Track,SeaJob.Salvage,Unload),
            Landfall("bread-fire","The Release Oven","Mik has kept the second oven dark. Without a door to go back to, a round loaf can be a cruel kind of notice.",
                "Oven Mastiff","Behind the damper is a bundle of letters offering spare beds. Nobody in the registry thought they required postage.",7,
                At(Haul,West,"Damper bundle","Lift the letters out of the damper"),At(Brace,East,"Oven shelf","Hold the shelf clear while Mik sorts them"),At(Turn,Crane,"Bed list","Enter the offers of rooms in the release book")),
            Crossing("bread-houses",SeaDuty.Convoy,"Doors Still Open","Mik wants every offer checked before he bakes. The prison skiff carries a different door knocker for each street around the bar.",
                "Take the skiff to the households and collect their replies.","Latch Ling","Some doors have changed color. Every knocker comes back with a scrap of curtain tied to it.",8,SeaJob.Guide,Relay,Relieve),
            Landfall("bread-bar","The First Round Loaf","Mik’s own release is stamped on the last page of the old register. He has never baked a loaf in his own shape.",
                "Flour Weevil","He cuts his loaf into enough pieces for the queue. Nell finds him later at the table, asleep with his hand on the round tin.",7,
                At(Seat,West,"Door-shaped tin","Seat the dented tin in the hot oven"),At(Turn,East,"Mik’s release","Read the last page to Mik"),At(LandingAction.Guide,Stairs,"First walk home","Walk the cook to the door with the curtain scrap")))
    ];
}
