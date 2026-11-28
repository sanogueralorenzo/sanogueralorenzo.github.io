using A=BoatsNBeasts.Core.LandingAction;
using S=BoatsNBeasts.Core.YardSite;
using J=BoatsNBeasts.Core.SeaJob;
using D=BoatsNBeasts.Core.SeaDuty;

namespace BoatsNBeasts.Core;

public static partial class FarLedger
{
    const string CalvingName="The Calving Sea";
    static CampaignArc Calving()=>CampaignArc.Create(CalvingName,"An island small enough to hold",
        "The returning islands make a ring of cliffs. Inside the ring the sea is shallow enough to stand in. Pip steps over the rail with her shoes in her hand. Something the size of a dinner plate starts following her.",
        "A pebble that has grown a single white sail",
        new("Pip  /  keeper of the small chart","Which boat should enter the nursery first?",
            "Toma's anchor tender has the strongest hull in the fleet. Nell's old post skiff has a patched bottom and the sound of a human household. The calves move toward whichever crew starts to sing.",
            "Take the working tender","Row in with the post","Toma puts every shackle away. The biggest boat in the fleet now carries one warm blanket.",
            "Six households give the post boat a different lullaby. The oarsmen gradually agree on a key."),16,[
            Crossing("wake-calf-rim",D.Sounding,"An open circle","Lio has never seen water this shallow so far from a shore. There are eleven islands in the ring. They count twelve shadows.",
                "Sound the passage between the traveling islands.","Ringback Whelk","The twelfth shadow is beneath the water. An island is giving birth.",6,J.Sound,J.Track,J.Relay),
            Landfall("wake-calf-first","One foot out of the water","Pip's small follower has two feet and a third thing which might be a foot tomorrow. A fishing net catches over its head.",
                "Nursery Heron","The little calf stands on the deck for one full breath. Nell puts its first footprint in the margin of the ledger.",6,
                At(A.Brace,S.West,"Lead weights","Hold the lead edge off the calf"),At(A.Cut,S.East,"Mesh","Cut the tangled mesh clear"),At(A.Guide,S.Stairs,"Warm shallows","Walk the newborn into the shallows")),
            Crossing("wake-calf-tender",D.Blockade,"An anchor tender with empty racks","The old examination chain still stretches across the nursery mouth. Toma knows which link she forged the morning after the flood.",
                "Open the chain from the deck of the working tender.","Linkbreaker Auk","Toma pockets one link. She lays it on the galley's fire grating where it makes a perfectly good place to stand the kettle.",7,J.Cut,J.Relay,J.Relieve),
            Landfall("wake-calf-sleep","The first dark","The calves sleep with their feet in hollows worn by older generations. The harbor survey has filled the hollows with little stone monuments.",
                "Monument Turtle","By sundown each hollow holds a calf. The monuments make excellent seats for people who want to watch them sleep.",7,
                At(A.Haul,S.Crane,"Survey stones","Lift the stones out of the sleeping hollows"),At(A.Brace,S.East,"Warm spring","Hold back the spring until the beds drain"),At(A.Guide,S.Stairs,"Last calf","Bring the last sleeper to its hollow")),
            Crossing("wake-calf-mouth",D.Hunt,"A mouth full of home","A sheltering adult has mistaken the lightship for a calf. It is carrying the ship inside its mouth, very carefully. The people inside would still like to be rescued.",
                "Follow the sheltering island and show it the calving signal.","The Long Mother","The Mother sets the lightship down inside the ring. An enormous eye stays open until every lantern is relit.",7,J.Track,J.Bait,J.DriveOff),
            Crossing("wake-calf-free",D.Convoy,"Cast off the last shore","The warm current has reached the ring. Sixteen watches of neighbors spread their boats in two loose lines. There is room between them for an island to turn.",
                "Bring the nursery herd through the two lines and home to the tide.","The Old Breakwater","The old breakwater takes its first step in three hundred years. Last Light swings to its moorings and follows. Pip puts a clean sheet on the crew table.",8,J.Tow,J.Guide,J.Relieve)
        ],Crossing("wake-calf-post",D.Convoy,"A song in a small boat","The last pilot through the nursery wrote down no depths at all. She left a song with a long rest in it for the calves to breathe.",
            "Bring the singing skiffs across the nursery mouth.","Cradleback Ray","The schoolchildren sing until a calf interrupts with a note of its own. They start again on the calf's note.",7,J.Tow,J.Guide,J.Relieve));

    static IslandStory[] CalvingIsles()=>[
        Isle(CalvingName,16,"Warmthumb Shoal","Wem Coil, nursery gardener",
            "Wem is trying to weed his vegetable plot. Every time he pulls up a turnip, two tiny reefs follow his hand for another.","A turnip with a tooth mark shaped like a bay",
            new PostLetter("a turnip seed","I meant to plant one row for the house and one row for the calves. They aren't old enough to read the little labels. Could you make some different seeds?","Wem paints the farmhouse green. The calves come for breakfast and let the turnips grow."),
            Crossing("wake-thumb-root",D.Salvage,"Turnips on the tide","A furrow has come loose. Wem has spent ten years growing a perfectly straight row and would like it back.","Recover the floating furrow before the calves scatter it.","Rootling Skate","Wem finds that the last three turnips are growing upside down. He calls it a trial plot.",6,J.Track,J.Salvage,J.Unload),
            Landfall("wake-thumb-plot","The other garden","The little reefs eat the white worms under the field. Wem needs narrow channels between the beds so the calves can swim as they eat.","Rootbed Mole","There is room under each bridge for one hungry calf and a mouthful of shade.",6,
                At(A.Cut,S.West,"Drain slots","Cut narrow slots between the beds"),At(A.Brace,S.East,"Bank boards","Brace the new banks"),At(A.Turn,S.Stairs,"Irrigation wheel","Flood the garden channels")),
            Crossing("wake-thumb-graze",D.Convoy,"A field for breakfast","In the dark the tide washes the furrow into open water. Wem takes his breakfast there and waits for the school to follow.","Shepherd the grazers to the drifting beds.","Cabbage Shark","The gardeners come home with full baskets and the calves with muddy noses.",7,J.Tow,J.Guide,J.Relieve),
            Landfall("wake-thumb-step","The wide doorstep","Wem is making a ramp so a calf that has grown feet can still come to breakfast.","Stepstone Adder","The first grown calf lies half in the kitchen door. Nobody gets past it until the kettle boils.",6,
                At(A.Haul,S.Crane,"Garden stones","Drag the stones to the kitchen wall"),At(A.Seat,S.West,"Low step","Bed the lowest step under water"),At(A.Brace,S.East,"Ramp","Hold the ramp as the tide rises"))),
        Isle(CalvingName,16,"Thimble Haven","Nix Dare, ship measurer",
            "Nix measures each newborn island in thimblefuls of displaced water. The smallest calf has swallowed her only thimble and now rattles when it swims.","A thimble polished on the inside",
            new PostLetter("a strip of marked twine","The little one grew another inch while I was making the record. How do you measure something that is always growing?","Nix ties a second knot with plenty of loose string beyond it. The rest is for tomorrow."),
            Crossing("wake-thimble-note",D.Sounding,"Something rattles","Nix can tell this calf from all the others by the rattle of tin against stone. The outer shoals are loud with stones.","Follow the tin note through the sounding grounds.","Tin Tongue","The thimble has caught in a tuft of moss on the calf's chin. It thinks it has grown a bell.",6,J.Sound,J.Track,J.Relay),
            Landfall("wake-thimble-wick","A measuring bath","The stone bath is full of yesterday's rain. Nix has to let the rain out and get exactly today's sea in.","Gauge Shrimp","The calf displaces one thimble, a splash and a quantity of laughter.",6,
                At(A.Turn,S.West,"Rain plug","Open the plug for yesterday’s rain"),At(A.Haul,S.Crane,"Pail","Bring in a pail of nursery water"),At(A.Seat,S.East,"Bath marks","Set the brass marks on the side")),
            Crossing("wake-thimble-scale",D.Salvage,"Borrowing a scale","The large reef calves are much too big for the bath. A disused buoy has a set of graduations along its side.","Recover the measuring buoy and its counterweight.","Ballast Hound","The fleet measures its first grown calf. It weighs exactly as much as a pleasantly surprised lighthouse.",7,J.Salvage,J.Tow,J.Unload),
            Landfall("wake-thimble-door","Leave room to grow","Nix rules out the measuring marks on her doorframe. She starts low and keeps going until somebody has to fetch a ladder.","Lintel Crab","A name appears beside every mark. The top of the ladder is left blank.",6,
                At(A.Haul,S.Fallen,"Ladder","Haul the ladder against the door"),At(A.Brace,S.West,"Top rail","Steady the top rail"),At(A.Seat,S.Stairs,"First mark","Put the thimble beside the lowest mark"))),
        Isle(CalvingName,16,"Pelican Cot","Reet, night nurse",
            "Reet has brought a young reef ashore because it will not eat. It takes all the sheets off the washing line and arranges them in a heap by the back step.","A pillowcase sewn to the size of a reef",
            new PostLetter("a soft white feather","Nurse Reet, that was my mother's washing. I don't mind the little one having it. I would like to know if it helped.","Reet sends the feather back folded in a clean pillowcase. There is wet sand in it and a very good night's sleep."),
            Crossing("wake-pel-feather",D.Hunt,"What a reef dreams of","The calf is building a nest like the pelicans that hatched on its back. Its foster flock is somewhere along the windward reef.","Track the white flock from the feather trail.","Whitewing Barracuda","The first pelican lands gently on the little reef. The calf takes a mouthful of sea grass without noticing.",6,J.Track,J.Bait,J.DriveOff),
            Landfall("wake-pel-bed","A hospital for two sorts of bird","The ward's roof leaks and the pelicans prefer it that way. Reet has put the dry sheets on the wrong side.","Rafter Stork","A dry cot, a wet cot and a place between them. Reet calls the ward finished.",6,
                At(A.Turn,S.West,"Roof louvre","Turn the louvre toward the wet cot"),At(A.Brace,S.East,"Dry rail","Brace the rail above the dry sheets"),At(A.Guide,S.Stairs,"Foster flock","Walk the birds to the new ward")),
            Crossing("wake-pel-nest",D.Convoy,"Sick call at sea","A second calf has stopped eating. Reet takes the first to visit, with one pelican as a professional witness.","Escort the floating ward to the outer nest.","Bandage Eel","Two calves graze under a single untidy bird. Reet writes companionship across both charts.",7,J.Tow,J.Relieve,J.Guide),
            Landfall("wake-pel-roost","Visiting hours","A new shelf on the roof will let the birds visit whenever the calves call.","Visiting Auk","The sign says visiting hours begin at dawn. A penciled note underneath says pelicans cannot read.",6,
                At(A.Haul,S.Crane,"Rooftop shelf","Hoist the shelf past the gutter"),At(A.Seat,S.West,"Landing peg","Set the landing peg"),At(A.Cut,S.Stairs,"Old net","Cut away the last of the old bird net"))),
        Isle(CalvingName,16,"The Blue Hinge","Ol Brink, gate carpenter",
            "Ol has spent a lifetime making gates close. He has been asked to make a gate that will stay open when an island pushes its head through.","One hinge that swings both ways",
            new PostLetter("a pair of brass screws","Ol, when I was small you made a gate to keep me out of the boatyard. Now I am the one bringing the herd in. Could we use the same wood?","Ol has kept the plank with the small handprint. The carpenter signs his reply in the print's thumb."),
            Crossing("wake-hinge-post",D.Salvage,"Count the open doors","An old harbor gate has broken into fifteen floating leaves. Ol only wants the one that has never had a lock fitted.","Raise the free leaf and bring it into the nursery.","Pintle Pike","The free leaf has a handprint on each face. A child tried once from either side.",6,J.Track,J.Salvage,J.Unload),
            Landfall("wake-hinge-jig","The inside is outside","Ol's jig has a label for the inside and another for the outside. Neither is going to help.","Jig Terrier","The gate swings with a nudge from either side. Ol takes a long tea break and watches it work.",6,
                At(A.Cut,S.Fallen,"Old stop","Cut the old stop off the jig"),At(A.Seat,S.West,"Second pintle","Set a pintle on either face"),At(A.Turn,S.East,"Trial gate","Swing the trial gate both ways")),
            Crossing("wake-hinge-leaves",D.Blockade,"The last swinging bridge","The anchor tender has a gate of its own. It was made to keep the herd out. Ol has brought a very large screwdriver.","Open the tender gate and clear the herd's approach.","Bridgeback Shark","The calves drift past slowly enough to put wet noses against the rail. The anchor crews hold out their hands.",7,J.Cut,J.Relay,J.Guide),
            Landfall("wake-hinge-open","Always welcome","Ol marks the first and last calves to pass the new gate. He asks the little ones to leave their prints in the wet paint.","Wetpaint Seal","Ol sets down his brush. There are little marks all over the gate and not one of them needs painting over.",6,
                At(A.Haul,S.Crane,"Gate leaves","Hang the leaves on their pintles"),At(A.Brace,S.East,"Threshold","Keep the threshold clear for the little ones"),At(A.Turn,S.Stairs,"Blue hinge","Give the blue hinge its first public turn")))
    ];
}
