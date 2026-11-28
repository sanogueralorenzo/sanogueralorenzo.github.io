using A=BoatsNBeasts.Core.LandingAction;
using S=BoatsNBeasts.Core.YardSite;
using J=BoatsNBeasts.Core.SeaJob;
using D=BoatsNBeasts.Core.SeaDuty;

namespace BoatsNBeasts.Core;

public static partial class FarLedger
{
    const string TinmoonName="Tinmoon Anchorage";
    static CampaignArc Tinmoon()=>CampaignArc.Create(TinmoonName,"The bell under the moon",
        "Something under the nursery answers the moon once every tide. Diver Islet Marr hears a dinner bell inside it. The sound comes from the part of the old harbor that never came to the surface.",
        "A dinner bell with a limpet still living in its handle",
        new("Islet Marr  /  saturation diver","Who owns a sound from a lost city?",
            "The salvage fleet wants to raise the bell and give it to the families. Islet's divers have seen the nursery calves come to its note. Without it the little ones may swim straight past the feeding ground.",
            "Raise it for the families","Leave the note below","The widows come down to the quay with clean rags. Each is given a turn at the polishing.",
            "Islet hangs a listening tube over the rail. The families can hear their bell from dry land."),13,[
            Crossing("wake-tin-dive",D.Sounding,"A Sound Through Tin","Islet lays her cheek against a battered teapot. “No moon in it, just a very small harbor.” The tea leaves jump to the beat of a submerged bell.",
                "Take soundings around the drowned harbor.","Tinback Hake","Lio recognizes a town clock striking the half. It is seven hours slow, exactly the time the city spent falling.",5,J.Sound,J.Track,J.Relay),
            Landfall("wake-tin-plumb","Divers’ feet","The diving shoes in the old school hang from the ceiling. Seven pairs have gone missing, and six nearby calves have begun walking in circles.",
                "Soleplate Dog","The seventh pair pinches Lio's toes. The calves stand listening while Islet counts each shoe back onto its hook.",5,
                At(A.Haul,S.Crane,"Shoe rack","Lower the rack to the flooded floor"),At(A.Cut,S.West,"Kelp bindings","Cut the straps without losing the weights"),At(A.Seat,S.East,"School rail","Set the shoes where the next class can reach them")),
            Crossing("wake-tin-hoist",D.Salvage,"The half-hour bell","It is a little thing to have outlived a city. The widows have brought a washing basket to receive it.",
                "Secure the crown and raise the bell through the shoaling trench.","Toll Skate","The youngest widow strikes the rim with her wedding ring. Three calves turn their heads.",6,J.Salvage,J.Tow,J.Unload),
            Landfall("wake-tin-alley","The street that remembers","Toma Pike remembers one street by the rattle of its shutters. Under water all the shutters have opened the wrong way.",
                "Shutter Nautilus","At the end of the street is a shop with two doors. Toma counts the steps between them and whispers her brother's name.",6,
                At(A.Turn,S.East,"Brass shutters","Turn the shutters seaward"),At(A.Brace,S.West,"Storm lintel","Brace the lintel for Toma"),At(A.Guide,S.Stairs,"Old steps","Walk the old street beside her")),
            Crossing("wake-tin-note",D.Hunt,"Bring the deep note home","Islet's divers move by tapping on their air lines. A predator has learned how to tap the recall. Lio hears it call with his own hand.",
                "Track the false recall and bring the diving party to shelter.","Answering Conger","Vara teaches the divers a new recall with a rest in the middle. The one who waits for the answer is family.",7,J.Track,J.Bait,J.DriveOff),
            Crossing("wake-tin-rise",D.Convoy,"Windows lit below","The families have fixed lights in the upstairs windows of their drowned houses. A hundred boats have come to see. The air hoses have right of way.",
                "See the divers and their families safely through the raised lights.","The Night Inspector","Toma watches her kitchen window go dark. Her little brother would always have left it burning. She calls the fleet by his old whistle.",7,J.Tow,J.Guide,J.Relieve)
        ],Crossing("wake-tin-stay",D.Sounding,"One length of speaking tube","Islet wants to carry the sound, all the way to the people who used to live above it.",
            "Lay the listening tubes between the bell and the family boats.","Copperjaw Perch","The families listen to the half-hour bell and the softer bubbling noises on either side. Somebody is down there making breakfast.",6,J.Sound,J.Guide,J.Relay));

    static IslandStory[] TinmoonIsles()=>[
        Isle(TinmoonName,13,"Limpet Lane","Bo Marr, retired locksmith",
            "Every door on Bo's street has come loose except his own. He thinks the house remembers who owes it the rent.","A tin key with a limpet for a bow",
            new PostLetter("a knot of key ribbon","My house has traveled farther than I have. If it comes by your window, would you look to see whether I left the stove on?","Bo has gone to live on the post boat. Someone else's window now has his key hanging beside it."),
            Crossing("wake-limpet-door",D.Salvage,"A door at sea","Nine loose doors make a shifting raft. Bo knows the kitchens by the smell of their paint.","Raise the kitchen doors onto the salvage lighter.","Jamb Clam","A boy recognizes the knife marks where he measured his sisters.",5,J.Track,J.Salvage,J.Unload),
            Landfall("wake-limpet-lock","Bo's double bolt","The door is held fast by a limpet and a promise Bo made to his wife never to leave the house unlocked.","Hasp Limpet","Bo unlocks the door and the limpet stays where it is. It is quite content with the arrangement.",5,
                At(A.Haul,S.Crane,"Door lift","Raise the door out of the surf"),At(A.Seat,S.West,"Brass ward","Seat Bo’s thin key"),At(A.Turn,S.East,"Second bolt","Turn the bolt from inside")),
            Crossing("wake-limpet-lighter",D.Convoy,"Nine kitchens afloat","The families turn the doors into the tables for a shared meal. The steamer with the good soup is upriver.","Tow the tables to the soup steamer.","Stockpot Cormorant","Bo sets out his wife's spoons. There are just enough if the smallest children share.",6,J.Tow,J.Relieve,J.Guide),
            Landfall("wake-limpet-wall","A wall for the last door","Bo would like his house to have a front door again. The builders have been saving him a place in the new mess hall.","Latch Barnacle","The first person through is carrying two cakes and can't manage the key. Bo props the door wide open.",6,
                At(A.Haul,S.West,"Frame","Haul the frame across the mess"),At(A.Brace,S.East,"Joint","Brace the new joint for Bo"),At(A.Turn,S.Stairs,"Kitchen door","Swing the old door into the new hall"))),
        Isle(TinmoonName,13,"Halfpast Buoy","Rill Tan, watch porter",
            "Rill delivers the correct time in tins. An open tin will set every clock on the block. Her latest delivery is half an hour of a Tuesday that hasn't happened yet.","Rill’s spare half-hour spoon",
            new PostLetter("half a paper clockface","Every time I see my sister I have to run to catch the tide. May I borrow half an hour and pay you back one quiet Sunday?","Rill sends a timetable with the last boat crossed out. Her sister can stay where she is."),
            Crossing("wake-half-tins",D.Sounding,"The Tuesday shelf","Warm water has made the tin lids pop. Tuesday is running half an hour ahead of its tide.","Chart the tide before the heat reaches the other tins.","Minute Mullet","The other tins still rattle when shaken. Time has not all gone out of them.",6,J.Sound,J.Track,J.Relay),
            Landfall("wake-half-coil","Sunday in the spring","A gull has wound the public clock with a strip of tin. Its chicks are asking for breakfast twice an hour.","Pendulum Gull","The gull has taken to announcing lunch. The children think this an improvement.",5,
                At(A.Brace,S.Fallen,"Clock spring","Brace the spring before it unwinds"),At(A.Cut,S.East,"Tin strip","Cut the scrap clear"),At(A.Seat,S.West,"Winder","Fit the clockmaker's winder")),
            Crossing("wake-half-due",D.Blockade,"Overdue by one minute","An inspector has impounded yesterday. The fleet cannot sail with the log stamped tomorrow.","Clear the inspection markers and release the clock boat.","Date Crab","The inspector has to sign for the return of a perfectly good day.",6,J.Cut,J.Relay,J.Guide),
            Landfall("wake-half-market","The market hour","Rill opens her tins together so everyone can take time for supper. The market bell has been chained to its noticeboard.","Market Cockle","When the bell rings nobody looks at the clock. They look at who sat down beside them.",6,
                At(A.Cut,S.West,"Noticeboard","Cut the clock chain free"),At(A.Haul,S.Crane,"Supper bell","Lift the bell to market height"),At(A.Turn,S.East,"Red tin","Open the market hour"))),
        Isle(TinmoonName,13,"Awl Bank","Vim Deller, suit stitcher",
            "Vim stitches diving suits while their occupants are still in them. A diver has returned with a small round window neatly sewn into the back of his suit. Something is looking out.","A round blue button with a view of deep water",
            new PostLetter("a blue-backed button","Vim, I have outgrown my suit. A very young fish has moved into one boot. Can you let me out without putting the fish out too?","Vim has fitted a sleeve for the fish. It is the first suit she has made with two owners written on the label."),
            Crossing("wake-awl-spool",D.Salvage,"Thread that swims","Vim's waxed thread keeps winding itself round the ship. The free end trails toward the creature that sewed the window.","Follow the thread and recover the diving spool.","Tailor Pipefish","The pipefish shakes the thread loose. It has sewn its brood into the safest nursery it could find.",5,J.Track,J.Tow,J.Salvage),
            Landfall("wake-awl-sleeve","Another sleeve","Vim needs an old sail, a brass washer and exactly one uninterrupted breath.","Button Shrike","The little eye at the window blinks. The diver asks for a mirror so he can blink back.",5,
                At(A.Haul,S.Fallen,"Sailcloth","Lay the cloth on the bench"),At(A.Seat,S.East,"Gasket","Seat the washer in its seam"),At(A.Brace,S.Crane,"Pump handle","Hold a steady breath on the handle")),
            Crossing("wake-awl-family",D.Convoy,"Two passengers to a suit","The brood is ready for open water. Vim travels in the diving bell with a pocket full of buttons.","Escort the brood to the night nursery.","Sleeve Squid","One youngster swims a clean circle round Vim's boot. The mother leads the others after it.",6,J.Tow,J.Relieve,J.Guide),
            Landfall("wake-awl-pane","One more alteration","The diver wants to keep the little window. It was the first time he has known what his own wake looks like.","Porthole Eel","Vim turns the pane into a mirror that looks out. She makes a second one for herself.",6,
                At(A.Turn,S.West,"Window catch","Open the old window catch"),At(A.Haul,S.Crane,"Mirror","Bring the small mirror across"),At(A.Seat,S.Stairs,"Back seam","Stitch the mirror into the seam"))),
        Isle(TinmoonName,13,"The Pewter Rooms","Min Dove, bath attendant",
            "The bathhouse sank with all the taps running. Its guests still come in the evening to warm their hands over the ascending bubbles.","Two taps on a chain, marked WARM and WARMER",
            new PostLetter("a worn bath token","Miss Dove, do I still have my usual tub? I have learned to swim since the bathhouse went down and I bring my own towel.","Min sends back the token bright as new. She has written a time on the towel instead."),
            Crossing("wake-pewter-taps",D.Sounding,"Follow the warm water","Bubbles from the wrong tap smell of lavender. Min can locate an entire street by its taste in soap.","Chart the warm vents above the bathhouse.","Lather Skate","The lavender tubs are still on the left. Even at the bottom of the sea the cold tap sticks.",6,J.Sound,J.Track,J.Relay),
            Landfall("wake-pewter-cold","The tap that sticks","Min never trusted the cold tap. A colony of bath beetles has built a warm cupboard around it.","Cistern Beetle","The cold comes back. A little cloud of lavender drifts through the changing room.",5,
                At(A.Cut,S.Fallen,"Pipe wrap","Open the old wrapping"),At(A.Haul,S.Crane,"Cold pipe","Lift it clear of the cupboard"),At(A.Turn,S.East,"Cold tap","Turn the cold tap one quarter")),
            Crossing("wake-pewter-guests",D.Convoy,"Usual customers","The regulars ask for the evening boat. Min checks coats at the bow and loans towels at the stern.","Bring the bathing boats into the warm-water circle.","Towel Ray","The bathers sit with their hands in the water and tell the same stories they always did.",6,J.Tow,J.Guide,J.Relieve),
            Landfall("wake-pewter-robes","Hooks for the robes","A bathhouse without a floor still needs somewhere to hang a coat. Min calls the carpenters to the surface platform.","Pegfoot Gull","The first hook is low enough for a child. The second is low enough for a very small diver.",6,
                At(A.Haul,S.West,"Oak rail","Haul the rail from the stores"),At(A.Brace,S.East,"Platform","Brace the platform on the tide"),At(A.Seat,S.Stairs,"Coat hooks","Set the row of coat hooks")))
    ];
}
