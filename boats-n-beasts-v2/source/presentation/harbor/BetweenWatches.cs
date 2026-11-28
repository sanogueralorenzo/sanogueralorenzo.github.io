using BoatsNBeasts.Core;

namespace BoatsNBeasts;

internal partial class LastLightHarbor
{
    int Watches(Shipmate mate)=>CrewWatches.For(mate).Select((_,i)=>Ledger.Campaign.NightWatches.ContainsKey($"{mate}-{i}")).TakeWhile(b=>b).Count();
    void NightWatch()
    {
        string equipped=Ledger.Campaign.OnWatch==Shipmate.None ? "" : $" {Ledger.Campaign.OnWatch} has the next watch with you.";
        Open("THE CREW TABLE","Between watches","Lio coils a dry line, Vara turns the broth down, and Nell has put her pencil away. Even the bell is quiet."+equipped);
        foreach(var mate in new[]{Shipmate.Lio,Shipmate.Vara,Shipmate.Nell})Choice(mate.ToString(),()=>ShipmateWatch(mate));
        Choice("Back to the quay",Close);
    }
    void ShipmateWatch(Shipmate mate)
    {
        var log=Ledger.Campaign;int index=Watches(mate);var all=CrewWatches.For(mate);
        if(index<all.Length && CrewWatches.Thresholds[index]<=log.SettledPorts().Count())
        {
            var scene=all[index];
            Open(mate.ToString().ToUpperInvariant()+"   /   OFF WATCH",scene.Title,scene.Scene);
            void Set(bool far)
            {
                UpdateLedger(Ledger with { Campaign=log with { NightWatches=new(log.NightWatches){[$"{mate}-{index}"]=far} } });
                Open(mate.ToString().ToUpperInvariant()+"   /   OFF WATCH",scene.Title,
                    (far?scene.FarResult:scene.NearResult)+(index==1?"  "+mate+" leaves a keepsake for your next watch.":""));
                if(index==1)Choice("Take the keepsake",()=>
                {
                    UpdateLedger(Ledger with {Campaign=Ledger.Campaign with {OnWatch=mate}});
                    Open(mate.ToString().ToUpperInvariant()+"   /   ON WATCH",CrewWatches.Token(mate),CrewWatches.Help(mate)+" Press F during play, once per charted departure.");
                    Choice("Return to the quay",Close,true);Choice("Stay with the crew",NightWatch);
                },true);
                else Choice("Sit a little longer",()=>ShipmateWatch(mate),true);
                Choice("Leave the table",Close);
            }
            Choice(scene.Near,()=>Set(false),true);Choice(scene.Far,()=>Set(true));
            if(index>=2 && log.OnWatch!=mate)Choice("Carry the keepsake",()=>
            { UpdateLedger(Ledger with {Campaign=log with {OnWatch=mate}});NightWatch(); });
            Choice("Another evening",NightWatch);
        }
        else
        {
            int at=Math.Max(0,index-1);var last=all[at];bool far=log.NightWatches.GetValueOrDefault($"{mate}-{at}");
            string memory=far?last.FarResult:last.NearResult;
            string hand=index>=2?$"  {CrewWatches.Token(mate)}. {CrewWatches.Help(mate)} Press F during a charted run, once per departure.":"";
            Open(mate.ToString().ToUpperInvariant()+"   /   OFF WATCH",index>=2?CrewWatches.Token(mate):last.Title,memory+hand);
            if(index>=2 && log.OnWatch!=mate)Choice("Carry this keepsake",()=>
            {
                UpdateLedger(Ledger with { Campaign=log with { OnWatch=mate } });NightWatch();
            },true);
            if(index>=2 && log.OnWatch==mate)Choice("Return the keepsake",()=>
            {
                UpdateLedger(Ledger with { Campaign=log with { OnWatch=Shipmate.None } });NightWatch();
            });
            if(index>1)Choice("Remember an earlier watch",()=>LookBack(mate,index-2));
            Choice("Back to the table",NightWatch);
        }
    }
    void LookBack(Shipmate mate,int page)
    {
        var scene=CrewWatches.For(mate)[page];bool far=Ledger.Campaign.NightWatches[$"{mate}-{page}"];
        Open(mate.ToString().ToUpperInvariant()+"   /   RECOLLECTION",scene.Title,scene.Scene+"  "+(far?scene.FarResult:scene.NearResult));
        if(page>0)Choice("An earlier evening",()=>LookBack(mate,page-1));
        Choice("Back to the present",()=>ShipmateWatch(mate),true);
    }
}
