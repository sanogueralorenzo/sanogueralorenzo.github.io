using static BoatsNBeasts.Core.SeaJob;
using static BoatsNBeasts.Core.YardSite;
using static BoatsNBeasts.Core.LandingAction;

namespace BoatsNBeasts.Core;

public static partial class FarLedger
{
    static IslandStory[] TangleloomIsles() => [
        Isle("Tangleloom Sound",5,"Buttonhole Bight","Sib, apprentice fastener",
            "Every sail in this bight buttons to the mast. Sib has inherited the button factory and the one button in town nobody knows how to undo.","A four-hole button mended down the middle",
            Crossing("button-under",SeaDuty.Salvage,"The Button Beneath","Sib’s grandmother kept a maker’s sample at the bottom of the bight. She said it was the safest possible pocket.",
                "Raise the sunken sample card from the anchor beds.","Mother-of-Pearl Ray","The card holds one broken button. Both pieces have been polished by someone's thumb.",6,Track,SeaJob.Salvage,Unload),
            Landfall("button-seam","A Fastener That Opens","The factory shutter fastens from the outside and the inside at once. Sib's grandmother built it after the foremen locked the night shift in.",
                "Latch Eater","It takes one hand on each side. Sib steps inside and leaves her grandmother's half of the button with the workers.",6,
                At(Haul,West,"Shutter cord","Haul the inside cord over the lintel"),At(Brace,East,"Twin catch","Hold one side while Sib turns the other"),At(Turn,Crane,"Maker’s mark","Read the maker’s mark inside the shutter")),
            Crossing("button-fleet",SeaDuty.Hunt,"The Missing Fasteners","Someone has taken every starboard button from the fishing fleet. Sib finds a trail of perfectly matched pearl discs.",
                "Follow the trail and recover the button baskets.","Cuff Crab","The crab is decorating its burrow. Lio trades it the largest buckle on his spare boot.",6,Track,Bait,DriveOff),
            Landfall("button-trial","Two Hands Aboard","A squall tears a buttonhole longer than a person. Sib proposes to mend it with the split button from the sample card.",
                "Pearl Borer","The sail holds. Sib drills four new holes beside the crack so the next pair can mend it again.",7,
                At(LandingAction.Cut,West,"Torn selvage","Cut the ragged edge back to sound canvas"),At(Seat,East,"Split button","Seat the split button under the patch"),At(Brace,Crane,"Trial sail","Brace the sail while the fishing crew takes the strain"))),
        Isle("Tangleloom Sound",5,"Spindle Ferry","Hal, retired stretcher bearer",
            "Six hammocks swing under the ferry. Hal remembers bringing six injured weavers across the strike line. The official log records six empty beds.","A hammock knot tied around a ship’s nail",
            Landfall("spindle-beds","The Bed Census","The town wants to turn the ferry into a ward. The clerk will license it only if Hal can prove the beds once held people.",
                "Blanket Tick","One hammock has six names sewn beneath the stretcher pole. Hal recognizes every crooked letter.",6,
                At(Haul,West,"Stretcher poles","Lift the poles from the false floor"),At(LandingAction.Cut,East,"Old mattress","Open the hem beneath the mattress"),At(Turn,Crane,"Stitched names","Read the six names into Nell’s book")),
            Crossing("spindle-six",SeaDuty.Convoy,"Visiting Hours","The six former passengers plan to attend the licensing hearing in person. None is prepared to let any of the others carry an umbrella.",
                "Bring the passenger ferry through the rain line.","Rainbob","They arrive soaked and carrying six perfectly dry umbrellas.",6,Tow,Relieve,SeaJob.Guide),
            Crossing("spindle-fluid",SeaDuty.Salvage,"A Jug of Clear Water","The hearing ends when the old ward tank begins to weep dye. The clean cistern is in a wreck where the ferry used to tie.",
                "Recover the clean cistern and deliver it upright.","Blue Pipet","Hal drinks the first cup. Nobody laughs when he offers the next one to an empty hammock.",7,Sound,SeaJob.Salvage,Unload),
            Landfall("spindle-first","Admission Number One","The registry clerk slips on the wet gangway. He insists on finishing the paperwork from bed and asks whether his handwriting has to be stitched.",
                "Ward Bobbin","Hal sews the clerk's name below the others. The first entry in the new log is a discharge.",7,
                At(Seat,West,"Clean tank","Seat the new cistern above the ward"),At(Turn,East,"Bed ledger","Open the ward ledger"),At(LandingAction.Guide,Stairs,"First patient","Help the first patient down the clean gangway"))),
        Isle("Tangleloom Sound",5,"Dyer’s Thumb","Lume, color steward",
            "Lume’s thumb is permanently purple. She can tell a boat's home by its sail dye, but the water round the island has begun to bleach every sail white.","A card of eight colors with a thumbprint in the middle",
            Crossing("dyer-plume",SeaDuty.Sounding,"A White Wake","The bleach plume has the shape of a tidy printed arrow. Lume knows tides are seldom that considerate.",
                "Sound both sides of the plume to locate its source.","Chalkfin","The arrows point back to a sorting barge that pays by the number of white sails delivered.",7,Sound,Track,Relay),
            Landfall("dyer-vats","Color by the Spoon","Lume keeps a spoon from each dye vat on a ring at her belt. One spoon has come back exactly the color of a customs uniform.",
                "Indigo Skink","The sorting barge has been drinking out of all eight vats through one hose.",6,
                At(Haul,West,"Intake hose","Pull the intake hose off the vat rim"),At(Brace,East,"Overflow gate","Brace the overflow while Lume drains the lye"),At(Turn,Crane,"Spoon rack","Match the stained spoon to its vat")),
            Crossing("dyer-return",SeaDuty.Blockade,"Every Color Home","The barge has wrapped the confiscated sails round its hull. Lume follows the purple strip that once tied her own front door shut.",
                "Recover the colored bundles from the sorting barge.","Whitestrake","The sails come free in one long ribbon. From the air the whole bay looks like a carpet being shaken out.",7,SeaJob.Cut,DriveOff,Unload),
            Landfall("dyer-mix","The Ninth Vat","Eight villages arrive to claim eight sail bundles. One bundle is purple in the sun and green in the shade. Two families remember making it.",
                "Madder Mite","Lume sets up a ninth vat for mixed households. Pip dips one finger and leaves a print beside Lume’s.",6,
                At(Seat,West,"Vat plug","Seat the plug in the spare mixing vat"),At(Haul,East,"Shared sail","Hoist the two-family sail above the dyehouse"),At(Turn,Crane,"Color card","Enter the ninth color on Lume’s card"))),
        Isle("Tangleloom Sound",5,"Needle Eye","Paz, ropewalker",
            "Paz walks the ferry lines carrying messages between two quarrelling villages. She has worn a groove in the rope above the exact place each side stops listening.","A length of speaking line with an ear-shaped loop",
            Crossing("needle-drop",SeaDuty.Salvage,"The Words That Fell","A letter dropped halfway between villages is still hanging from the lowest part of the crossing rope. Its seal belongs to neither shore.",
                "Catch the dropped letter before the line touches water.","Lowline Kite","Both villages have addressed the envelope to Paz. There is nothing written on the inside.",6,Track,SeaJob.Salvage,Relay),
            Landfall("needle-rail","One Step Wider","Paz admits the blank page is an invitation to speak for herself. She wants to ask for a handrail. Her left knee has begun to shake.",
                "Tightwire Wasp","The first rail is a little too high. Children on both sides offer to lower it together.",6,
                At(Haul,West,"Handline coil","Haul the spare coil onto the crossing"),At(Seat,East,"Guide post","Seat a guide post at a child’s shoulder"),At(Brace,Crane,"Crossing rope","Brace Paz’s crossing while she tests the handrail")),
            Crossing("needle-run",SeaDuty.Convoy,"Letters on the Water","While the crossing is shut, the two villages have to exchange messages by boat. The first mailbag is full of suggested names for the bridge.",
                "Shepherd the temporary mail ferry through the needle rocks.","Threadspout","The bag balances only after Vara puts a brick in with the shorter names.",7,SeaJob.Guide,Relieve,Tow),
            Landfall("needle-voice","Speaking Distance","The rail carries a voice farther than a shouted message. Paz ties an ear loop at either end and steps off the crossing.",
                "Spool Widow","At dusk both villages hear Paz singing from her kitchen. The new bridge gets her name without a vote.",7,
                At(LandingAction.Cut,West,"Old toll twine","Cut the toll twine off the handrail"),At(Turn,East,"Listening cup","Open the cup on the far shore"),At(LandingAction.Guide,Stairs,"Last crossing","Walk beside Paz on her last official crossing")))
    ];
}
