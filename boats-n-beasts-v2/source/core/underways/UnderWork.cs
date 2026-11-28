using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed partial class UnderwayRun
{
    public Vector2 Reader=>new(-.1f,-2.26f);
    public Vector2 Rotary=>new(0,.03f);
    public float MillBeat=>(Clock*.73f+Room.Seed%6)%MathF.Tau;
    public Vector2 LoadAt(int i)=>new(MathF.Cos(MillBeat+i*MathF.PI)*1.76f,MathF.Sin(MillBeat+i*MathF.PI)*1.39f);
    public bool LoadLive=>!Room.Cleared&&Room.Trial==UnderTrial.Capstan&&Room.Step is >=1 and <=3;
    public string GuardianName=>Depth+1==Floors?Order.Boss:Mark(Depth)+((Depth%3) switch{0=>" Rook",1=>" Rack Beetle",_=>" Winch Hound"});
    public string Hint
    {
        get
        {
            var r=Room;if(AtSurfaceLift)return "The shaft opens to daylight. Choose a witness road or the bonded yards";
            if(Extracting)return Depth+1==Floors?"Recover the cargo at the lift and board":"Use the cleared lift to descend";
            if(r.Trial>=UnderTrial.Drain)return ChamberHint();
            if(SealsReady&&!ProofFiled&&r.Cleared)return FieldHint;
            if(r.Trial==UnderTrial.Mouth)return Staff?"Follow a gallery for both colors of seal":"Choose a crew workshop to earn the staff key";
            if(r.Trial==UnderTrial.Camp)return "Trade or decipher the two seal impressions at the archive";
            if(r.Trial==UnderTrial.Stores)return r.Gift?"Find another route into the galleries":"Choose one free fitting at the workbench";
            if(r.Cleared)return WardsReady?"Find the lower gate and fit your seals and filed report":$"Chart the remaining seals · {Keys}/{SealCost}";
            if(r.Trial==UnderTrial.Watch)return "Split the watch. Lio can interrupt a wind-up";
            if(r.Trial==UnderTrial.Keeper)return r.Step switch{1=>"Brace the left anchor with Lio, signal Vara at the right",2 when Quiet=>"Take the guardian’s register and run it to the lift",_=>"Read the keeper’s wind-up and break its guard"};
            if(r.Trial==UnderTrial.Mirrors)return r.Step==0?"Turn the three mirrors to light the brass receiver":"Read the illuminated stencil at the receiver";
            if(r.Trial==UnderTrial.Freight)return r.Board!.Matched<2?"Push or pull both loads onto the brass sockets":"Stamp the delivery at the weighing desk";
            return r.Trial switch{
                UnderTrial.Chart=>r.Step switch{0=>"Read the three witness plates around the room",1=>"Ring the three plates in the order recorded",_=>"Ask Vara to print the complete rubbing"},
                UnderTrial.Capstan=>r.Step switch{0=>"Hook the counterweight at "+Mark(r.Code[0]),1=>"Signal Vara at "+Mark(r.Code[1])+" to tension the line",2=>"Take the loose crank at "+Mark(r.Code[2]),_=>"Fit the crank at the center drum"},
                UnderTrial.Rescue=>r.Step switch{0=>"Call Vara to hold the bent frame",1=>"Cut the two straps without letting the frame fall",2=>"Speak to the trapped worker",_=>Quiet?"Lead the worker to the rescue sling":"Keep the ambush off the escape route"},
                _=>r.Step switch{0=>"Cut the brake ties on the cargo cradle",1=>"Hook the cradle onto the towline",2=>"Tow the load to the turning plate and signal Vara",_=>Quiet?"Deliver the sealed load to the rising platform":"Defend the load and bring it to the lift"}
            };
        }
    }
    public IEnumerable<(Vector2 At,string Label)> WorkMarks()
    {
        var r=Room;
        if(AtSurfaceLift){yield return(Winch,"E  Witness road  ·  2  Bonded yards");yield break;}
        if(Extracting){yield return(Winch,Depth+1==Floors?"E  Extract":"E  Descend");yield break;}
        if(r.Trial>=UnderTrial.Drain){foreach(var mark in CaseMarks())yield return mark;yield break;}
        if(r.Trial==UnderTrial.Mouth){yield return(WardDesk,"E  Read floor chart");yield break;}
        if(r.Trial is UnderTrial.Camp or UnderTrial.Stores)
        {
            if(!r.Gift)yield return(FittingBench,"1 / 2 / 3  Choose fitting");
            if(r.Trial==UnderTrial.Camp&&!r.Clue)yield return(WardDesk,"E  Compare seal impressions");
            yield break;
        }
        if(r.Cleared)yield break;
        switch(r.Trial)
        {
            case UnderTrial.Mirrors:
                if(r.Step==1)yield return(r.Board!.Receiver,"E  Read lit stencil");
                else for(int i=0;i<3;i++)yield return(r.Board!.GlassAt(i),"E  Pivot mirror");
                break;
            case UnderTrial.Freight:
                if(r.Board!.Matched==2)yield return(WardDesk,"E  Stamp delivery");else for(int i=0;i<2;i++)if(!r.Board.Sockets.Contains(r.Board.Blocks[i]))yield return(r.Board.At(r.Board.Blocks[i]),"J  Push · K  Pull");
                break;
            case UnderTrial.Chart:
                if(r.Step==0){for(int i=0;i<3;i++)if(!r.Lit[i])yield return(Pad(i),"E  Inspect "+Mark(i));}
                else if(r.Step==1){for(int i=0;i<3;i++)yield return(Pad(i),"E  "+Mark(i));}
                else yield return(Reader,"L  Make rubbing");
                break;
            case UnderTrial.Capstan:
                yield return(r.Step==3?Rotary:Pad(r.Code[r.Step]),r.Step switch{0=>"K  Brace load",1=>"L  Wind drum",2=>"E  Lift crank",_=>"E  Fit crank"});break;
            case UnderTrial.Rescue:
                if(r.Step==1){for(int i=0;i<2;i++)if(!r.Lit[i])yield return(Pad(r.Code[i+1]),"J  Cut strap");}
                else yield return(r.Step switch{0=>Pad(r.Code[1]),2=>r.Escort,_=>Winch},r.Step switch{0=>"L  Hold frame",2=>"E  Help worker",_=>"Escort to sling"});break;
            case UnderTrial.Cradle:
                yield return(r.Step switch{0=>Pad(r.Code[0]),1=>r.Cargo,2=>Pad(r.Code[2]),_=>Winch},r.Step switch{0=>"J  Cut brake ties",1=>"K  Catch towline",2=>"L  Change track",_=>"E  Deliver load"});break;
            case UnderTrial.Keeper:
                if(r.Step==1){if(!r.Lit[0])yield return(Pad(0),"K  Hold anchor");if(!r.Lit[1])yield return(Pad(1),"L  Ratchet anchor");}
                if(Quiet&&r.Step>=2)yield return(WardDesk,"E  Recover register");
                break;
        }
    }
    bool Operate()
    {
        var r=Room;if(CaseAction(true,false,false,false))return true;
        if(r.Trial==UnderTrial.Mouth&&Near(WardDesk,1.0f))
        {Say($"The two front workshops issue a staff key. Bring {SealCost} seals of both colors to the lower gate. The gold doors on M show where. One ration restores 5 vitality with 1.");return true;}
        if(r.Trial==UnderTrial.Camp&&Near(WardDesk,1))
        {
            if(r.Clue)Say("The archive has already paid the witness fee.");
            else if(!BothWards)Say("Bring one brass and one blue impression. Nell can read the route out of the marks.");
            else{r.Clue=true;Finds++;silver+=3;Powder++;Log("Paired impressions traced the keeper’s return lane.");Say("The reversed impressions match. Nell recovers 3 silver and a powder charge from the mapped locker.");}return true;
        }
        if(r.Cleared)return false;
        switch(r.Trial)
        {
            case UnderTrial.Mirrors:
                if(r.Step==1&&Near(r.Board!.Receiver,1.02f)){Clear();return true;}
                for(int i=0;i<3&&r.Step==0;i++)if(Near(r.Board!.GlassAt(i),.73f)){r.Board.Rotate(i);if(r.Board.Reached==1){r.Step=1;Say("The far stencil glows. Read its impression at the receiver.");}return true;}
                break;
            case UnderTrial.Freight when r.Board!.Matched==2&&Near(WardDesk,1):Clear();return true;
            case UnderTrial.Chart:
                for(int i=0;i<3;i++)if(Near(Pad(i),.88f))
                {
                    if(r.Step==0)
                    {r.Lit[i]=true;int stamp=Array.IndexOf(r.Code,i)+1;Say($"{Mark(i)} bears witness stamp {stamp}.");if(r.Lit.All(x=>x)){r.Step=1;Log(string.Join(" → ",r.Code.Select(Mark)));Say("All three depositions are copied. Ring the plates in witness order. M opens the notes.");}}
                    else if(r.Step==1){if(r.Code[r.Read]==i){r.Read++;if(r.Read==3){r.Step=2;Say("The three voices agree. Have Vara strike the printing frame.");}else Say("The next witness can answer.");}else{r.Read=0;Say("Two voices overlap. Consult the notes on M and begin again.");}}
                    return true;
                }
                break;
            case UnderTrial.Capstan:
                if(r.Step==2&&Near(Pad(r.Code[2]),1)){r.Step++;Say("Crank in hand. Mind the two swinging weights at the center drum.");return true;}
                if(r.Step==3&&Near(Rotary,.90f)){Clear();return true;}break;
            case UnderTrial.Rescue when r.Step==2&&Near(r.Escort,1.05f):
                r.Step=3;r.Leads=true;AddFoe(0,false);AddFoe(1,false);Say("Two guards have heard the rescue bell. Lead the worker past them to the lit sling.");return true;
            case UnderTrial.Cradle when r.Step==3&&Near(Winch,1.05f)&&Quiet&&Vector2.Distance(r.Cargo,Winch)<1.87f:Clear();return true;
            case UnderTrial.Keeper when Quiet&&r.Step>=2&&Near(WardDesk,1.10f):
                Clear();Extracting=true;Say(Depth+1==Floors?Order.Objective:"The keeper leaves a route register. Take it to the clay lift to open the next deck.");return true;
        }
        return false;
    }
    bool ToolWork(bool line,bool signal,bool cut)
    {
        var r=Room;if(r.Cleared)return false;if(CaseAction(false,cut,line,signal))return true;
        void HookPoint(Vector2 target){Hook=.47f;HookEnd=target;HookWait=.70f;}
        if(r.Trial==UnderTrial.Freight&&(line||cut))
        {
            var board=r.Board!;int i=Vector2.DistanceSquared(board.At(board.Blocks[0]),Player)<Vector2.DistanceSquared(board.At(board.Blocks[1]),Player)?0:1;
            var p=board.At(board.Blocks[i]);if(Near(p,line?2.52f:1.03f)){if(line)HookPoint(p);if(!board.Shift(i,Player,line))Say("The crate meets a stop. Work a different side or hook it back.");else if(board.Matched==2)Say("Both sockets are loaded. The scale desk will issue the stamp.");return true;}
        }
        if(r.Trial==UnderTrial.Capstan)
        {
            if(r.Step==0&&line&&Near(Pad(r.Code[0]),1.45f)){HookPoint(Pad(r.Code[0]));r.Step++;return true;}
            if(r.Step==1&&signal&&Near(Pad(r.Code[1]),1.10f)){r.Step++;Flash=.35f;return true;}
        }
        if(r.Trial==UnderTrial.Chart&&r.Step==2&&signal&&Near(Reader,1.15f)){Clear();return true;}
        if(r.Trial==UnderTrial.Rescue)
        {
            if(signal&&r.Step==0&&Near(Pad(r.Code[1]),1.06f)){r.Step=1;Flash=.4f;return true;}
            if(cut&&r.Step==1)for(int i=0;i<2;i++)if(!r.Lit[i]&&Near(Pad(r.Code[i+1]),1.06f)){r.Lit[i]=true;if(r.Lit[0]&&r.Lit[1])r.Step=2;return true;}
        }
        if(r.Trial==UnderTrial.Cradle)
        {
            if(cut&&r.Step==0&&Near(Pad(r.Code[0]),1.18f)){r.Step=1;return true;}
            if(line&&r.Step==1&&Near(r.Cargo,2.85f)){HookPoint(r.Cargo);r.Step=2;return true;}
            if(signal&&r.Step==2&&Near(Pad(r.Code[2]),1.22f)&&Vector2.Distance(r.Cargo,Pad(r.Code[2]))<2.2f){r.Step=3;Flash=.38f;AddFoe(0,false);return true;}
        }
        if(r.Trial==UnderTrial.Keeper&&r.Step==1)
        {
            if(line&&!r.Lit[0]&&Near(Pad(0),1.90f)){HookPoint(Pad(0));r.Lit[0]=true;}
            else if(signal&&!r.Lit[1]&&Near(Pad(1),1.50f)){r.Lit[1]=true;Flash=.4f;}else return false;
            if(r.Lit[0]&&r.Lit[1]){r.Step=2;foreach(var guard in r.Foes)guard.Stagger=1.75f;Say("The brace peels open. Cut through the exposed guard.");}return true;
        }
        return false;
    }
}
