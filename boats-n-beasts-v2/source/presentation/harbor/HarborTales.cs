using BoatsNBeasts.Core;

namespace BoatsNBeasts;

internal partial class LastLightHarbor
{
    void Keeper()
    {
        Open("NELL SPINDLE   /   KEEPER OF THE TOLL", "A counting error",
            "Nell has laid out a row of shells on the paving stones. “I counted boats for thirty years. Always from up there. Never noticed how many people fit in one.”");
        Choice("Sit beside her", () =>
        {
            Open("NELL SPINDLE", "The names in the margin",
                Ledger.Dedicated ? "She tips the shells into a child's two hands. “You can have the lot. I'm going down to meet the next boat.”"
                : "“When the fares went up I started keeping a second book. All the names of people we turned away. Do you think Vara would want it?” She holds it out with both hands.");
            Choice(Ledger.Dedicated ? "Help her to the pier" : "Bring it to the crew", Ledger.Dedicated ? Close : Crew, true);
        }, true);
        if (Ledger.Dedicated) { Choice("Read the visitors’ book", () => VisitorsBook(0)); Choice("Join the night watch",NightWatch); }
        Choice("Let her count", Close);
    }
    void Crew()
    {
        if (Ledger.Dedicated && Ledger.Campaign.NeedsHearing) { Listen(); return; }
        if (Ledger.Dedicated && Ledger.Campaign.NeedsCharter) { Ending(); return; }
        if (Ledger.Campaign.HomePortNamed && Ledger.Campaign.Next==null && !Ledger.Campaign.StoryCleared) { TideEnding(); return; }
        if (Ledger.Dedicated && Ledger.Campaign.Voyages.Length > 0) { MessTable(); return; }
        if (Ledger.BellReleased && !Ledger.Dedicated)
        {
            Open("VARA   /   AT THE BELL FRAME", "Who gets the first pull?", Ledger.Promise == CrewPromise.RememberTheMissing
                ? "You promised the families a roll call. Vara sets the list beside the rope. Her brother’s name is at the top."
                : "Lio sets a chipped cup beneath the bell. The water shivers before anyone touches the rope. Every boat in the bay has turned to listen.");
            Choice("Read the names together", () => Dedicate(true), true);
            Choice("Give the rope to the children", () => Dedicate(false));
        }
        else if (Ledger.Dedicated)
        {
            Open("LIO   /   FIRST WATCH", "Room at the table", Ledger.Dedication == BellDedication.Children
                ? "“Heard the small ones this morning? They’ve invented a fourth signal. It means the bread is out of the oven.” Lio leaves a coil of clean rope on the lowest hook."
                : "The list has grown. Beneath the names of the drowned, someone has begun writing the names of people who came home. Vara finds yours and laughs.");
            Choice("Stay for a bowl", Close, true);
            Choice("Meet the visiting pilot", Guest); Choice("Join the night watch",NightWatch);
        }
        else if (Ledger.HasTongue && Ledger.Promise == CrewPromise.Unspoken)
        {
            Open("VARA   /   BELLFOUNDER", "A mark under the bronze", "“That’s my maker’s stamp. I cast this bell to call boats home. The Warden turned it into a toll and my brother rowed out without a fare. What will we ring it for?”");
            Choice("For everyone still missing", () => Promise(CrewPromise.RememberTheMissing), true);
            Choice("For the boats coming home", () => Promise(CrewPromise.WelcomeHome));
        }
        else if (Ledger.HasTongue)
        {
            Open("LIO   /   SALVAGE DIVER", "A diver’s promise", Ledger.Promise == CrewPromise.RememberTheMissing
                ? "“I’ll carry the list. If we have to swim, paper goes in my hat. Never lost my hat.”"
                : "“Coming home. I like that. My mother used to leave a lamp in a pickle jar. Ugly thing. I could see it for miles.”");
            Choice("To the chart", Chart, true); Choice("Leave the table", Close);
        }
        else
        {
            string[] lines = [
                "“Fog last night. Three skiffs tried to find us by ear. We pulled two off the teeth. The third is still out there.” Vara taps the empty bell frame with a spoon.",
                "“I went under for the tongue. A wreck sprouted legs and walked away with my whole salvage line. I’d have followed, but Vara was standing on the other end.”",
                "“I pulled him up by his trousers. His hand was still closed around a rivet.” Vara rolls it across the chart. It stops on Lantern Sound."
            ];
            Open(crewLine == 1 ? "LIO   /   SALVAGE DIVER" : "VARA   /   BELLFOUNDER", "The silent watch", lines[crewLine]);
            if (crewLine < 2) Choice(crewLine == 0 ? "Ask Lio about the wreck" : "Look at the rivet", () => { crewLine++; Crew(); }, true);
            else Choice("Unroll the chart", Chart, true);
            Choice("Leave the table", Close);
        }
    }
    void Promise(CrewPromise value)
    {
        UpdateLedger(Ledger with { Promise = value }); Crew();
    }
    void Dedicate(bool names)
    {
        bell.Stream=QuayTone.Note(74,true);bell.Play();
        UpdateLedger(Ledger with { Dedication = names ? BellDedication.RollCall : BellDedication.Children });
        Open("CHAPTER I   /   THE SILENT WATCH", "A sound across the teeth", names
            ? "They read until Vara’s spoon goes cold. From the fog comes a ragged answering note. The third skiff rows into the light with a kettle tied to the mast."
            : "Three children hang from the rope together. Out beyond the reef a kettle answers, struck with an oarlock. The third skiff has found its way home.");
        Choice("Welcome them in", Close, true);
    }

    void MessTable()
    {
        var log = Ledger.Campaign;
        var last = FarLedger.Find(log.Voyages[^1]);
        string text = log.Homecoming(last);
        var arc = FarLedger.Arcs.First(region => region.Region == last.Region);
        if (last.Id == arc.Orders[^1].Id) text += " The crew has kept a souvenir. " + arc.Keepsake + ".";
        Open(arc.Title.ToUpperInvariant(), "Word from the quay", text);
        Choice("Take your watch", FarChart, true);
        Choice("Meet the visiting pilot", Guest); Choice("Join the night watch",NightWatch);
        Choice("Read the visitors’ book", () => VisitorsBook(0));
        if(log.Voyages.Any(id=>FarLedger.Find(id).Flotilla))Choice("Read the fleet register",()=>FleetRegister(int.MaxValue));
    }

    void Guest()
    {
        var log = Ledger.Campaign;
        int port = Visitors.At(log);
        var guest = Visitors.All[port];
        string answer = !log.Decisions.TryGetValue(FarLedger.Arcs[port].Region, out var second) ? guest.Early : second ? guest.Second : guest.First;
        Open(guest.Job.ToUpperInvariant(), guest.Name, guest.Question + "  " + answer);
        Choice(guest.Reply, Close, true);
    }
    void Ending()
    {
        var log = Ledger.Campaign;
        Open("LAST LIGHT QUAY   /   THE HOMECOMING", "Where is home on the chart?",
            "Every pilot crowds around the table. The compass needle spins once, slowly, and points straight at the bell rope. Pip has saved room in the margin. She wants to know what to write.");
        void Write(bool crew)
        {
            UpdateLedger(Ledger with { Campaign = log with { CrewSigned = crew } });
            bell.Stream=QuayTone.Note(74,true);bell.Play();
            string ringing = Ledger.Dedication == BellDedication.Children ? "The children hang on the rope together." : "Vara reads the names and rings for each one.";
            string signatures = crew ? "The page fills with thumbprints, flour and one wet paw." : "Pip writes LAST LIGHT in a hand big enough to read from the gangplank.";
            Open("THE FAR LEDGER   /   CHART SIGNED", crew ? "Room for one more" : "A name on the door", signatures + " " + ringing +
                " Oren sets another place. Nell opens the register to a clean page and props the door open with it. On the tide outside, a strange little boat is looking for somewhere to tie up.");
            Choice("Throw them a line", () =>
            {
                Open("THE WALKING TIDE", "Land in the wake",
                    "The visitor aboard the little boat holds out a flowerpot. Under its soil a baby reef is swimming in circles. Across the bay the whole lighthouse takes one quiet step to the west. Nell puts down her pen. “Fetch the bigger chart.”");
                Choice("Open the outer chart",FarChart,true); Choice("Step onto the quay",Close);
            }, true);
        }
        Choice("Write Last Light Quay", () => Write(false), true);
        Choice("Ask the crew to sign", () => Write(true));
    }
}
