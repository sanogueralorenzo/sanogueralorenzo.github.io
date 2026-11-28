using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed partial class UnderwayRun
{
    public bool GalleryOpen=>Floor.Rooms[14].Cleared||Floor.Rooms[15].Cleared;
    public bool CacheRecovered=>Floor.Rooms[16].Cleared;
    public bool ProofFiled=>Floor.Rooms[17].Cleared;
    public bool SealsReady=>Keys>=SealCost&&BothWards;
    public string CaseItem=>Order.Evidence?.Item??LandingRegion.From(Order.Region).Tally;
    public string CaseMark=>Order.Evidence?.Mark??("A double punch in the "+Mark(0)+" stamp.");
    public string CaseFinding=>Order.Evidence?.Finding??Order.Objective;
    public string EvidenceRecord{get;private set;}="";
    public string CaseStage=>Depth switch{0=>"Trace",1=>"Backing",2=>"Object",3=>"Provenance",_ when Depth+1==Floors=>"Finding",4=>"Witness",_=>"Impression"};
    public string FieldHint=>!GalleryOpen?"Work the parcel exchange or pressure orchard to open the submerged cache":!CacheRecovered?"Trace the marked object inside the submerged cache":!ProofFiled?"Carry the recovered sample to the assay office and file its weight":"The deck’s evidence is filed";
    public string Parcel=>Depth switch{0=>"a tracing of the mark",1=>"the maker’s backing strip",2=>CaseItem,3=>"a matching counterfoil",_ when Depth+1==Floors=>"the crew’s signed finding",4=>"the witness slip",_=>"the original impression"};
    public Vector2 SampleDesk=>new(0,-2.20f);
    public Vector2 CartBell=>new(2.90f,1.77f);
    public Vector2 AssayDesk=>new(.02f,-1.82f);
    public string ChamberHint()
    {
        var r=Room;
        if(r.Cleared)return ProofFiled?"The evidence for this deck is filed":FieldHint;
        return r.Trial switch{
            UnderTrial.Drain=>r.Pipes!.Ready?"Set the bypass with Vara at the pump":"Turn joined pipes until the blue supply feeds every gold drain",
            UnderTrial.Rail=>r.Rail!.Done?"Read the last parcel receipt at the signal bell":$"Set the points for {SwitchRail.Berth(r.Rail.Asked)} and ring the dispatch bell  ·  {r.Rail.Delivered}/{r.Rail.Manifest.Length}",
            UnderTrial.Dig=>r.Step switch{0=>"Read the survey note for this deck’s cache",1=>"Inspect the three marked seams. One matches the note",2=>"Set Lio on the matching seam and have Vara hold the cap",_=>Quiet?"Bag the sample under the marked seam":"Keep the breakwater watch away from the open seam"},
            _ when !CacheRecovered=>"Recover a sample from the submerged cache",
            _ when r.Mosaic is {} torn=>torn.Restored?"File the restored chart at the reader":"Slide the eight plates into print order, 1–8 across the rows. Leave the last slot open",
            _=>r.Balance!.Complete?"Take the stamped sample from the pans and file the report":$"Balance the sample at {Signed(r.Balance!.Target)}. J loads the left, K the right; repeat to unload"
        };
    }
    public static string Signed(int n)=>n>0?"+"+n:n.ToString();
    public int RockIndex=>Room.Code[(Depth+1)%3];
    public Vector2 Notebook=>new(-2.73f,1.67f);
    public IEnumerable<(Vector2 At,string Label)> CaseMarks()
    {
        var r=Room;if(r.Cleared)yield break;
        switch(r.Trial)
        {
            case UnderTrial.Drain:
                if(r.Pipes!.Ready){yield return(SampleDesk,"L  Set bypass");yield break;}
                int joint=Enumerable.Range(0,16).MinBy(i=>Vector2.DistanceSquared(Player,DrainageBoard.At(i)));
                yield return(DrainageBoard.At(joint),r.Pipes.Bolted[joint]?"Fixed joint":"E  Turn joint");break;
            case UnderTrial.Rail:
                yield return(CartBell,r.Rail!.Done?"E  Take receipt":r.Rail.Rolling?"Parcel in transit":$"L  Send to {SwitchRail.Berth(r.Rail.Asked)}");
                int point=Enumerable.Range(0,7).MinBy(i=>Vector2.DistanceSquared(Player,r.Rail.At(i)));yield return(r.Rail.At(point),"E  Throw point");break;
            case UnderTrial.Dig:
                if(r.Step==0){yield return(Notebook,"E  Read the survey");yield break;}
                if(r.Step==1){for(int i=0;i<3;i++)yield return(Pad(i),"E  Inspect "+Mark(i));yield break;}
                if(r.Step==2){yield return(r.Lit[0]?Pad((RockIndex+1)%3):Pad(RockIndex),r.Lit[0]?"L  Hold cap":"K  Catch seam");yield break;}
                if(Quiet)yield return(Pad(RockIndex),"E  Wrap "+Parcel);
                break;
            case UnderTrial.Assay:
                if(!CacheRecovered){yield return(AssayDesk,"Sample needed");yield break;}
                if(r.Mosaic is {} torn)
                {
                    if(!torn.Restored)
                    {
                        int plate=Enumerable.Range(0,9).MinBy(i=>Vector2.DistanceSquared(Player,TornChart.At(i)));
                        if(torn.Tiles[plate]>0)yield return(TornChart.At(plate),$"E  Slide {torn.Tiles[plate]}");
                    }
                    yield return(AssayDesk,torn.Restored?"E  File restored chart":"K  Undo  ·  L  Read grain (1 chit)");yield break;
                }
                var scale=r.Balance!;
                if(!scale.Complete)for(int i=0;i<3;i++)yield return(scale.At(i),$"{scale.Mass[i]}  ·  {(scale.Pan[i]==0?"rack":scale.Pan[i]<0?"left":"right")}");
                yield return(AssayDesk,scale.Complete?"E  File report":$"L  Weigh  {Signed(scale.Reading)} / {Signed(scale.Target)}");break;
        }
    }
    bool CaseAction(bool use,bool cut,bool hook,bool signal)
    {
        var r=Room;if(r.Cleared)return false;
        switch(r.Trial)
        {
            case UnderTrial.Drain:
                var board=r.Pipes!;
                if(signal&&board.Ready&&Near(SampleDesk,1.0f)){Clear();Powder++;Say("Vara wedges the sluice. The cache drains and the crew gains a charge for the side hatches.");return true;}
                if(!use)return false;
                int joint=Enumerable.Range(0,16).MinBy(i=>Vector2.DistanceSquared(Player,DrainageBoard.At(i)));
                if(!Near(DrainageBoard.At(joint),.67f))return false;
                if(board.Bolted[joint])Say("This casting is riveted to the floor. The adjoining elbows turn.");else board.Turn(joint);return true;
            case UnderTrial.Rail:
                var rail=r.Rail!;
                if(signal&&Near(CartBell,1.10f)&&!rail.Done){if(rail.Launch())Say("Vara rings "+SwitchRail.Berth(rail.Asked)+". The cart takes whichever points lie ahead of it.");return true;}
                if(use&&rail.Done&&Near(CartBell,1.10f)){Clear();Rations++;Say("The dispatcher gives the crew a lunch tin and opens the freight door to the submerged cache.");return true;}
                if(!use||rail.Done)return false;
                int point=Enumerable.Range(0,7).MinBy(i=>Vector2.DistanceSquared(Player,rail.At(i)));
                if(!Near(rail.At(point),.78f))return false;rail.Throw(point);return true;
            case UnderTrial.Dig:
                int mark=RockIndex;
                if(use&&r.Step==0&&Near(Notebook,1)){r.Step=1;Log($"{CaseStage} survey · {Mark(mark)} carries the impression.");Say($"The survey records {CaseMark.TrimEnd('.')} at the {Mark(mark)} seam.");return true;}
                if(use&&r.Step==1)for(int i=0;i<3;i++)if(Near(Pad(i),.80f))
                {if(i==mark){r.Step=2;Say("The old cut matches. Let Lio catch it while Vara takes the next pillar.");}else Say("The surface runs smooth here. The note on M names the marked seam.");return true;}
                if(hook&&r.Step==2&&!r.Lit[0]&&Near(Pad(mark),1.4f)){r.Lit[0]=true;HookEnd=Pad(mark);Hook=.45f;return true;}
                if(signal&&r.Step==2&&r.Lit[0]&&Near(Pad((mark+1)%3),1.10f)){r.Step=3;Flash=.35f;AddFoe(0,false);if(Depth%2==1)AddFoe(1,false);Say("The old watch heard the cap fall. Keep the seam open until the sample is safe.");return true;}
                if(use&&r.Step==3&&Quiet&&Near(Pad(mark),1.05f)){Clear();Log("Recovered "+Parcel+".");Say("Wrapped "+Parcel+". The exchange door leads to the assay pans.");return true;}
                return false;
            case UnderTrial.Assay:
                if(!CacheRecovered)return false;
                bool complete=r.Mosaic?.Restored??r.Balance!.Complete;
                if(use&&complete&&Near(AssayDesk,.89f))
                {
                    Clear();Finds++;EvidenceRecord=Depth+1==Floors?CaseFinding:Depth==0?CaseMark:$"{Parcel} · {CaseItem}";
                    Log(EvidenceRecord);Say(Depth+1==Floors?CaseFinding:$"Nell files {Parcel} with the report on {CaseItem}. The seal court can now read this deck.");return true;
                }
                if(complete)return false;
                if(r.Mosaic is {} torn)
                {
                    if(Near(AssayDesk,.89f)&&hook){if(torn.Undo())Say("Lio draws the last plate back along its runner.");return true;}
                    if(Near(AssayDesk,.89f)&&signal)
                    {
                        if(Chits==0)Say("The restorer asks one work chit to trace the next break in the grain.");
                        else if(torn.Suggested<0){Chits--;int tile=torn.ReadGrain();Say($"The grain beside plate {torn.Tiles[tile]} continues toward the empty square.");}
                        return true;
                    }
                    if(!use)return false;
                    int tileAt=Enumerable.Range(0,9).MinBy(i=>Vector2.DistanceSquared(Player,TornChart.At(i)));
                    if(!Near(TornChart.At(tileAt),.72f))return false;
                    if(!torn.Push(tileAt))Say("Only a plate beside the free runner can slide.");
                    else if(torn.Restored)Say($"The eight plates form the outline of {CaseItem}. File the impression at the reader.");
                    return true;
                }
                var scale=r.Balance!;
                if(signal&&Near(AssayDesk,1.05f))
                {
                    if(scale.Weigh()){Flash=.37f;Say(scale.Complete?"Both pans stand still. File the record at the desk.":"Vara stamps the reading. Weigh the next sample with the same brass pieces.");}
                    else Say($"The dial reads {Signed(scale.Reading)}; the stamped notch is {Signed(scale.Target)}.");return true;
                }
                if(hook||cut)for(int i=0;i<3;i++)if(Near(scale.At(i),.86f)){scale.Place(i,hook?1:-1);if(hook){Hook=.30f;HookWait=.31f;HookEnd=scale.At(i);}return true;}
                return false;
        }
        return false;
    }
}
