using static BoatsNBeasts.Core.SeaDuty;

namespace BoatsNBeasts.Core;

public static partial class FarLedger
{
    static CampaignArc Reedglass() => CampaignArc.Create("Reedglass Delta","The Paper River",
        "Every map of Reedglass ends at a neat blue line. Oren’s charcoal drawing shows houses under it. Nell borrows a basin and floats his drawing in the water. A second channel bleeds through.",
        "A reed whistle that sounds like a frog with a head cold",
        new("Pell  /  apprentice papermaker","Who keeps the dry copy?",
            "Pell can make one copy before the tide eats the letters. The ferry families need the map to come home. The mill hands want the poisoned channel marked where every shipwright will see it.",
            "Send it with the families","Hang it on the mill gate",
            "Pell rolls the map inside a fishing flute. Only the children remember the fingering that opens the end.",
            "By sunrise every plank in the mill gate has a black arrow painted on it. The workers have made a map you can walk on."),
        2,
        [
            Order("reed-sound",Sounding,"Water Beneath Water","Pell sits on a pontoon beating a saucepan. Silt has covered the old soundings. The last survey listed her neighborhood as navigable water.",
                "Take new soundings and find the submerged mill stairs.","Silt-Sieve Skate","The sounding lead comes up with a door knocker caught in the grease. Pell knows whose door.",5),
            Order("reed-rag",Landing,"The Rag Pickers","Parchment dries on the frames above a nest of ink-fed chicks. The parent bird has learned to unfold its wings across both exits.",
                "Free the rag pickers and carry their last dry sheet out of the mill.","Papermill Heron","Pell lays the sheet against the tavern wall. You can see the old street names in the window light.",5),
            Order("reed-flute",Convoy,"A Flute for the Ferryman","The map goes in a flute and the flute goes in a dog’s collar. Unfortunately the dog insists on visiting every fish barge in the delta.",
                "Get the map and the ferry families through the old cuts.","Mudfin Bailiff","Pell’s grandmother plays the map case. Three children insist the river is a note flat.",6),
            Order("reed-lock",Landing,"The Back of the Waterwheel","The nightly sluice is operated from a gallery behind the wheel. Oren left a brass thimble jammed in its ratchet, buying someone a single tide.",
                "Reach the ratchet gallery and release the backed-up channel.","Ratchet Egret","The thimble fits over a child’s finger. A six-fingered print, Vara realizes, was a small hand laid over a big one.",6),
            Order("reed-scow",Hunt,"The Walking Weir","The registry’s sounding scow runs on legs at low tide. Pell needs its striped tail board to reverse the false depths entered in the shipping register.",
                "Bring the striped datum board back to the mill stairs.","The Walking Weir","Countersigned by forty muddy thumbs, the survey restores the houses to the map.",6),
            Order("reed-press",Salvage,"Little Hands in the Pulp","The ruined paper press still holds a roll of passage stubs. Oren paid for two tickets to Hanging Orchard. The smaller ticket is stamped for a crate of pears.",
                "Raise the press rollers and recover the two passage stubs.","Coffer Carp","Lio folds the smaller stub into a bird. Written on its wing in a child's hand is one word. Pip.",5)
        ],
        Order("reed-strike",Blockade,"The Gate in the River","The mill hands have stopped the wheels. The inspection launch is coming upstream with a pot of white paint to erase their arrows.",
            "Break the inspection line and give the river witnesses a crossing.","Whitewash Pike","The arrows stay. The first cargo following them is a crate of clean drinking cups.",6));
}
