using BoatsNBeasts.Core;

namespace BoatsNBeasts;

internal partial class LastLightHarbor
{
    void TideEnding()
    {
        var log=Ledger.Campaign;
        Open("NELL SPINDLE   /   THE LAST MOORING", "Where should a moving island sleep?",
            "Pip kneels beside the youngest reef. It has grown one small barnacle in the shape of a house. Toma uncoils the last shackle and offers a hand. The nursery can follow the herd into open water. The islands can also agree on a season when everyone comes home.");
        void Finish(bool free)
        {
            UpdateLedger(Ledger with { Campaign=log with { FreeMigration=free } });
            bell.Stream=QuayTone.Note(74,true);bell.Play();
            string choice=free ? "The last buoy slips its mooring. Chartmakers leave a generous margin beside every island. The first message from the herd is a pressed flower with a wet postmark."
                : "The fleet meets on the turning of the warm current. The charts mark a season in place of a latitude. Toma brings dinner for four and finds herself laying places for forty.";
            string family=Ledger.Dedication==BellDedication.Children ? "The children ring the bell until a young reef answers from the dark." : "Vara rings once for those still at sea. Oren stands beside her for the last name.";
            Open("BOATS ’N’ BEASTS   /   THE WALKING TIDE",free?"Sea room":"A season for coming home",
                choice+" "+family+" Nell closes the book. Lio goes down to see what the island looks like from underneath.");
            Choice("Stay at Last Light",Close,true);Choice("Open the ship’s log",FarChart);
        }
        Choice("Give the herd sea room",()=>Finish(true),true);
        Choice("Keep a season for returning",()=>Finish(false));
    }
}
