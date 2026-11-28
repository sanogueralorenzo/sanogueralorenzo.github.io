using static BoatsNBeasts.Core.SeaDuty;

namespace BoatsNBeasts.Core;

public static partial class FarLedger
{
    static CampaignArc Sable() => CampaignArc.Create("Sable Court","The Trial of a Harbor",
        "Meret Gauge has charged Last Light Quay with impersonating a port. Her courthouse floats, because no island in the sound will grant it a lease.",
        "The court’s smallest weight, stamped with a sleeping fish",
        new("Nell Spindle  /  witness","Who takes the stand?",
            "Nell’s register proves the fees were collected on boats that never arrived. Pip remembers her father sailing several of them home. The court allows a single first witness.",
            "Call Nell and the register","Call Pip and her father",
            "Nell asks for a cushion, a glass of water and the name of the person who taught the examiner arithmetic.",
            "Pip stands on a tea chest. Her father takes off his hat. She takes it from him and uses it to catch the court’s leaking roof."),
        7,
        [
            Order("sable-writ",Hunt,"A Warrant with Oars","The tribunal’s clerk rows a black writ from harbor to harbor, confiscating gangplanks as evidence. He is running out of places to land.",
                "Intercept the writ and win a berth at the court’s public landing.","Ink Oarsman","The clerk stamps your summons on a piece of toast. Nell eats it in front of him.",7),
            Order("sable-dog",Landing,"Dog of the Bottom Step","The Bench Hound sits on a flight of steps made from impounded ballast. Every time a prisoner is released the steps rise and the hound loses its bed.",
                "Lift the detention keys and free the pilots waiting below the bench.","Bench Hound","Pip’s father emerges with a hound on a piece of string. It has been sleeping on his foot for six months.",7),
            Order("sable-ink",Salvage,"The Ink Never Lies","The original fee tables were tipped into the harbor when the examiners arrived. Nell can read the ink through water if someone holds the tables still.",
                "Raise the original fee tables for Nell’s testimony.","Abacus Eel","Nell reads two columns aloud. Nobody in the gallery needs to hear the third.",8),
            Order("sable-ballast",Landing,"The Weight of a Harbor","Gauge uses standard weights to decide how much a harbor is worth. The master weight is hollow. Something inside it keeps tapping.",
                "Open the weight room and bring its contents into the hearing.","The Brass Balance","Inside the weight is a little compass whose needle points at people waiting for someone to come home.",8),
            Order("sable-race",Convoy,"Adjournment on the Tide","Finding the court against her, Gauge orders its tug to tow the entire building out of jurisdiction. Half the witnesses are still on the upper deck.",
                "Get the witness boats alongside and keep the court in the sound.","Tug of Office","The hearing resumes in the galley. The bailiff writes the verdict on the back of Jo’s shopping list.",8),
            Order("sable-north",Sounding,"The Needle Points Down","The compass points through the bottom of the boat. Gauge has lowered the final page of the register into the Unnumbered Sea. Every unlisted port is due for removal at dawn.",
                "Take bearings on the sinking page and find the uncharted approach.","Sounding Hound","Vara puts Pip’s paper bird beside the compass. Its beak turns toward home.",8)
        ],
        Order("sable-pip",Convoy,"A Witness in Every Window","Pip remembers the colors of the kitchens on each boat she sailed. Take the court’s surveyor to see them before the examiners order a fresh coat of paint.",
            "Escort the kitchen witnesses through the bailiff’s inspection fleet.","Black Apron","When the court asks for proof, the cooks bring lunch. Several jurors request a second helping of evidence.",8));
}
