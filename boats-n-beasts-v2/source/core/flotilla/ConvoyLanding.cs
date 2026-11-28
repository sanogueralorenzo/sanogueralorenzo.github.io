using System.Numerics;

namespace BoatsNBeasts.Core;

public enum MusterRole { Unposted, Salvage, Escort, Fortify }
public enum MusterPhase { Rally, Work, Consign, Guard, Locks, Tideway, Embark, Won, Lost }
public sealed class MusterBoat(string name,string skipper,int index)
{
    public readonly string Name=name,Skipper=skipper;
    public readonly int Index=index;
    public int Hull=6,People,Stores,Timbers,Step;
    public int Flags;
    public MusterRole Role;
    public bool Ready,Through;public float SailedAt,LeftDock=-100;
    public Vector2 Worker,Passenger,Load;
}
public sealed partial class ConvoyLanding
{
    public readonly CampaignOrder Order;
    public readonly LandingRegion Region;
    public readonly MusterBoat[] Boats;
    public readonly int Seed,Districts;
    public readonly Loadout Outfit;
    public readonly List<YardBeastState> Foes=[];
    public readonly List<YardAttack> Attacks=[];
    public readonly List<Vector2> Drops=[];
    public LandingPlan Plan{get;private set;}=null!;
    public MusterPhase Phase{get;private set;}
    public int District{get;private set;}
    public int Silver{get;private set;}public int SilverEarned=>Silver;
    public int Health{get;private set;}public int Maximum{get;}
    public int Active{get;private set;}=-1;public MusterBoat? Team=>Active>=0?Boats[Active]:null;
    public bool Won=>Phase==MusterPhase.Won;public bool Lost=>Phase==MusterPhase.Lost;
    public float Condition=>Lost?0:Math.Clamp((Health/(float)Maximum+Boats.Sum(b=>b.Hull)/24f)*.5f,0,1);
    public int Alive=>Boats.Count(b=>b.Hull>0);
    public int Lead=>Boats[0].Hull>0?0:Carrier>=0&&Boats[Carrier].Hull>0?Carrier:Array.FindIndex(Boats,b=>b.Hull>0);
    public bool Last=>District+1==Districts;
    public int HeldLines{get;private set;}
    int brokenLines,requiredLines;bool commandTurn;
    public int Spares{get;private set;}public int LockPins{get;private set;}
    public ConvoyChannel? ChannelBoard{get;private set;}
    public float Clock,HookWait,DodgeWait,Flash,Swing,Hurt,Dashing,LineTime,EventTime;
    public Vector2 Player,Mate,Gunner,Heading=-Vector2.UnitY,LineEnd;
    public string Line="";
    float cutWait,signalWait,safe;Vector2 dashHeading;
    public ConvoyLanding(CampaignOrder order,int seed,int stores,Loadout loadout=Loadout.Standard,float startingCondition=1)
    {
        Order=order;Seed=seed;Outfit=loadout;Region=LandingRegion.From(order.Region);
        Districts=Math.Clamp(order.Legs,2,3);Maximum=12+Math.Clamp(stores,0,2)*2+(loadout==Loadout.Lifeboat?3:0);
        float strength=Math.Clamp(startingCondition,0,1);Health=Math.Max(1,(int)MathF.Ceiling(Maximum*strength));Spares=1+Math.Clamp(stores,0,2);
        Boats=Manifest(Region.Climate);
        if(order.Articles is {} charter)
        {
            Boats[0]=new(charter.Vessel,charter.Captain,0);
            Boats[1]=new(charter.ConsortVessel,charter.Consort,1);
        }
        foreach(var b in Boats)b.Hull=Math.Clamp((int)MathF.Ceiling(7*strength),1,8);
        Refit();
    }
    static MusterBoat[] Manifest(IslandClimate climate)
    {
        string manifest=climate switch{
            IslandClimate.Kiln=>"Biscuit Tin|Pip|Black Cuff|Yara|Milk Tooth|Soli",
            IslandClimate.Delta=>"Ink Goose|Edda|Rush Candle|Lem|Margin|Siu",
            IslandClimate.Orchard=>"Blue Bruise|Pav|Ladder Hen|Ulli|Windfall|Netta",
            IslandClimate.Shelf=>"Kettle Lid|Issa|Soft Rime|Tor|Warm Mitten|Nia",
            IslandClimate.Loom=>"Green Selvedge|Della|Last Button|Paz|Half Hitch|Ren",
            IslandClimate.Reef=>"Hush Bell|Toll|Deep Reed|Uma|Shell Spoon|Jori",
            IslandClimate.Court=>"Jury Box|Tev|Good Copy|Aru|Docket Bird|Maud",
            IslandClimate.Stars=>"Pocket North|Iro|Half Past|Low|Night Pin|Lumi",
            IslandClimate.Saltstep=>"Root Cup|Pia|Wet Step|Len|Planting Moon|Bo",
            IslandClimate.Bottlebrush=>"Glass Blister|Suri|Wet Wick|Jev|Blue Neck|Ola",
            IslandClimate.Waxwing=>"Soft Seal|Ketta|Yellow Quill|Fin|Folded Wing|Neri",
            IslandClimate.Narrows=>"Dream Hook|Emme|Cradle Song|Wen|Soft Shoe|Per",
            IslandClimate.Tinmoon=>"Thin Silver|Anni|Last Quarter|Tash|Deep Magnet|Nil",
            IslandClimate.Drumskin=>"Second Stick|Hani|Bent Rim|Sol|Reply Drum|Coro",
            IslandClimate.Pitchwake=>"Hot Rosin|Tav|Round Turn|Pela|Tar Shoe|Sef",
            _=>"First Foot|Ria|Small Reef|Esme|Open Palm|Jan"
        };
        var names=manifest.Split('|');return Enumerable.Range(0,3).Select(i=>new MusterBoat(names[i*2],names[i*2+1],i)).ToArray();
    }
    void Refit()
    {
        Plan=new(Order,District,Seed);ChannelBoard=null;HeldLines=brokenLines=requiredLines=0;commandTurn=false;Phase=MusterPhase.Rally;Active=-1;LockPins=0;Foes.Clear();Attacks.Clear();Drops.Clear();
        if(Plan.BrokenBridge>=0)Plan.Splice();
        Player=Plan.Dock;Mate=Player+new Vector2(.4f,-.3f);Gunner=Player+new Vector2(-.4f,-.2f);
        foreach(var b in Boats){b.Role=MusterRole.Unposted;b.Ready=b.Through=false;b.LeftDock=-100;b.Step=b.Flags=0;b.Worker=Officer(b.Index);b.Passenger=Mark(b.Index,0);b.Load=Mark(b.Index,1);}
        Say(District==0?Order.Brief:$"{DistrictName}. Bring the surviving boats alongside and give the crews their next jobs.");
    }
    public string DistrictName=>Region.Districts[(District+(int)((uint)Seed%(uint)Region.Districts.Length))%Region.Districts.Length];
    public Vector2 Officer(int i)=>Plan.Walkable(Plan.Patches[0].Center+new Vector2((i-1)*1.75f,-.68f+.40f*(i%2)));
    public Vector2 Station(int i)=>Plan.Patches[i==0?1:i==1?2:4].Center;
    public Vector2 Mark(int i,int n)
    {
        var patch=Plan.Patches[i==0?1:i==1?2:4];float angle=(n*2.1f+.42f*i+District*.65f);
        return patch.Closest(patch.Center+new Vector2(MathF.Cos(angle)*Math.Min(2.05f,patch.Radius.X*.66f),MathF.Sin(angle)*Math.Min(1.83f,patch.Radius.Y*.64f)));
    }
    public Vector2 GatePost(int i)=>Plan.Patches[3].Closest(Plan.Summit+new Vector2((i-1)*2.00f,.83f));
    public Vector2 Channel(int i,bool gate)=>Unit(new Vector2((i-1)*.70f,gate?-1:1));
    public Vector2 Bank(int i,bool gate)
    {
        var patch=Plan.Patches[gate?3:0];var axis=Channel(i,gate);return patch.Closest(patch.Center+axis*25);
    }
    public Vector2 Launch(int i)=>Bank(i,true)-Channel(i,true)*.32f;
    public Vector2 Mooring(int i,bool gate)=>Bank(i,gate)+Channel(i,gate)*1.00f;
    public string Objective=>Phase switch{
        MusterPhase.Rally=>"Call on each skipper. Give the boat a job with 1, 2 or 3.",
        MusterPhase.Work when Team==null=>"Choose a posted crew at its flag. Two finished jobs can cover the last boat.",
        MusterPhase.Work=>Team!.Role switch{MusterRole.Salvage=>"Recover the iron and choose how to spend it",MusterRole.Escort=>"Free the dock families and lead them past the watch",_=>"Raise a breastwork and seat its crossbeam"},
        MusterPhase.Consign=>CargoInstruction,
        MusterPhase.Guard when HeldLines!=0=>"The commander has grappled the boats. Free two skippers to peel the armor open",
        MusterPhase.Guard=>Last?$"Protect the flotilla from {Order.Boss}":"Drive the harbor watch off the lock",
        MusterPhase.Locks=>"Brace the tide gates with Lio and Vara, then turn the center wheel",
        MusterPhase.Tideway=>"Read the shoals, set the three rudders and signal the tide",
        MusterPhase.Embark=>"Release each surviving boat at its pennant, then board at the wheel",
        MusterPhase.Won=>Order.Objective,_=>"The muster has broken"
    };
    public IEnumerable<(Vector2 At,string Label)> Goals()
    {
        if(Phase==MusterPhase.Rally){foreach(var b in Boats.Where(b=>b.Hull>0&&b.Role==MusterRole.Unposted))yield return(Officer(b.Index),$"{b.Skipper} · 1 Salvage / 2 Escort / 3 Fortify");yield break;}
        if(Phase==MusterPhase.Work)
        {
            if(Team is {} b){foreach(var m in WorkMarks(b))yield return m;yield break;}
            foreach(var row in Boats.Where(b=>b.Hull>0&&!b.Ready))yield return(Station(row.Index),$"E  {row.Name} · {row.Role}");
            if(CanFight)yield return(Plan.Gate,"E  Call the convoy");yield break;
        }
        if(Phase==MusterPhase.Consign){foreach(var mark in FreightMarks())yield return mark;yield break;}
        if(Phase==MusterPhase.Guard){if(HeldLines!=0){foreach(var m in ReleaseMarks())yield return m;yield break;}foreach(var f in Foes)yield return(f.Position,f.Kind==YardBeast.Guardian?Order.Boss:"Raider");yield break;}
        if(Phase==MusterPhase.Locks){if((LockPins&1)==0)yield return(GatePost(0),"K  Brace ebb chain");if((LockPins&2)==0)yield return(GatePost(2),"L  Haul flood chain");if(LockPins==3)yield return(GatePost(1),"E  Turn tide wheel");yield break;}
        if(Phase==MusterPhase.Tideway&&ChannelBoard is {} basin)
        {
            foreach(var row in Boats.Where(b=>b.Hull>0&&!basin.Home(b.Index)))yield return(GatePost(row.Index),$"E  {row.Name} · {ConvoyChannel.Bearing(basin.Rudder[row.Index])}");
            yield return(Plan.Gate,"L  Signal the tide");yield break;
        }
        if(Phase==MusterPhase.Embark&&CargoAdrift)
        {
            if(!SalvagedLoose)yield return(Launch(Carrier),"K  Recover adrift consignment");
            else foreach(var boat in Boats.Where(b=>b.Hull>0))yield return(Launch(boat.Index),"E  Transfer to "+boat.Name);
            yield break;
        }
        if(Phase==MusterPhase.Embark&&Last&&!CargoDelivered&&Carrier>=0)yield return(Launch(Carrier),"L  Deliver "+CargoName);
        if(Phase==MusterPhase.Embark){foreach(var row in Boats.Where(b=>b.Hull>0&&!b.Through))yield return(Launch(row.Index),$"E  Release {row.Name}");if(Boats.All(b=>b.Hull==0||b.Through))yield return(Launch(Lead),Last?$"E  Board {Boats[Lead].Name}":$"E  Take passage on {Boats[Lead].Name}");}
    }
    public bool CanFight=>Boats.Count(b=>b.Ready&&b.Hull>0)>=Math.Min(2,Alive);
    public void Choose(int number)
    {
        if(Won||Lost||number<1||number>3)return;
        if(Phase==MusterPhase.Rally)
        {
            var b=Boats.Where(b=>b.Hull>0&&b.Role==MusterRole.Unposted).MinBy(b=>Vector2.DistanceSquared(Player,Officer(b.Index)));
            if(b==null||!Near(Officer(b.Index),1.26f))return;b.Role=(MusterRole)number;Say($"{b.Skipper} posts the {b.Name} to {b.Role.ToString().ToLowerInvariant()}.");
            if(Boats.All(b=>b.Hull<=0||b.Role!=MusterRole.Unposted)){Phase=MusterPhase.Work;Say("The skippers raise their lane pennants. Join a crew at its work flag.");}return;
        }
        if(Team is {Role:MusterRole.Salvage,Step:4} team&&Near(Station(team.Index),1.24f))
        {
            if(number==1){team.Hull=Math.Min(8,team.Hull+3);team.Stores++;}
            else if(number==2){Spares+=2;team.Stores++;}else{Silver+=5;team.Stores+=2;}Finish(team);return;
        }
        if(number==1&&Spares>0&&Health<Maximum){Spares--;Health=Math.Min(Maximum,Health+4);Say("The shipwright opens a rescue pack. Four vitality.");}
    }
    public void Interact()
    {
        if(Won||Lost)return;
        if(FreightAction('E')||FreeLine('E'))return;
        if(Phase==MusterPhase.Work)
        {
            if(Team is {} team){DoWork(team,'E');return;}
            var b=Boats.Where(b=>b.Hull>0&&!b.Ready).MinBy(b=>Vector2.DistanceSquared(Player,Station(b.Index)));
            if(b!=null&&Near(Station(b.Index),1.31f)){Active=b.Index;Say($"{b.Skipper} takes your line. {Objective}.");return;}
            if(CanFight&&Near(Plan.Gate,1.24f))
            {
                if(Carrier<0){Phase=MusterPhase.Consign;foreach(var hull in Boats.Where(v=>v.Hull>0&&v.LeftDock<0))hull.LeftDock=Clock;Say(CargoInstruction);}else BeginGuard();return;
            }
        }
        if(Phase==MusterPhase.Locks&&LockPins==3&&Near(GatePost(1),1.15f))
        {
            Phase=MusterPhase.Tideway;ChannelBoard=new(Plan.Seed,District,Region.Climate);Say($"The lock opens on {Order.Articles?.Refuge??DistrictName}. Set the colored signal posts, then call one tide at the wheel.");return;
        }
        if(Phase==MusterPhase.Tideway&&ChannelBoard is {} board)
        {
            var post=Boats.Where(b=>b.Hull>0&&!board.Home(b.Index)).MinBy(b=>Vector2.DistanceSquared(Player,GatePost(b.Index)));
            if(post!=null&&Near(GatePost(post.Index),.94f)){board.Turn(post.Index);Say($"{post.Skipper} sets the tiller {ConvoyChannel.Bearing(board.Rudder[post.Index])}. Watch the dotted courses before sounding.");}return;
        }
        if(Phase==MusterPhase.Embark)
        {
            var b=Boats.Where(b=>b.Hull>0&&!b.Through).MinBy(b=>Vector2.DistanceSquared(Player,Launch(b.Index)));
            if(CargoAdrift){Say("Recover the grounded consignment before releasing the surviving boats.");return;}
            if(b!=null&&Near(Launch(b.Index),1.10f)){
                if(b.Index==Carrier&&Last&&!CargoDelivered){Say($"Signal Vara here with L to deliver {CargoName} to {Refuge}.");return;}
                b.Through=true;b.SailedAt=Clock;Silver+=1+b.People;Say($"{b.Name} clears the gate with {b.People} passengers.");return;}
            if(b==null&&Lead>=0&&Near(Launch(Lead),1.18f)){if(Last){Phase=MusterPhase.Won;Say(Order.Objective);}else{District++;Refit();}}
        }
    }
    void BeginGuard()
    {
        foreach(var b in Boats.Where(b=>b.Hull>0&&!b.Ready)){b.Hull=Math.Max(1,b.Hull-2);if(b.LeftDock<0)b.LeftDock=Clock;}
        Phase=MusterPhase.Guard;Active=-1;Spawn(Last?YardBeast.Guardian:YardBeast.Porter,Plan.Summit+new Vector2(0,-1.70f));
        Spawn(YardBeast.Slinger,GatePost(0));if(Last||District>0)Spawn(YardBeast.Skater,GatePost(2));
        Say(Last?$"{Order.Boss} is on the lock. The skippers have brought the fittings you saved.":"The lock watch seizes the far chain. Keep them away from the convoy.");
    }
    public IEnumerable<(Vector2 At,string Label)> ReleaseMarks()
    {
        foreach(var b in Boats.Where(b=>b.Hull>0&&(HeldLines&(1<<b.Index))!=0))
        {
            var tool=b.Role switch{MusterRole.Fortify=>"J  Cut the gangway",MusterRole.Salvage=>"K  Lift the grapple",MusterRole.Escort=>"L  Signal the escape",_=>"E  Cast off the line"};
            yield return(Launch(b.Index),$"{tool} · {b.Skipper}");
        }
    }
    bool FreeLine(char key)
    {
        if(HeldLines==0)return false;
        foreach(var b in Boats.Where(b=>b.Hull>0&&(HeldLines&(1<<b.Index))!=0))
        {
            char tool=b.Role switch{MusterRole.Fortify=>'J',MusterRole.Salvage=>'K',MusterRole.Escort=>'L',_=>'E'};
            if(key!=tool||!Near(Launch(b.Index),1.4f))continue;
            if(key=='K')Tether(Launch(b.Index));if(key=='L')Flash=.4f;
            HeldLines&=~(1<<b.Index);brokenLines++;Silver++;
            if(brokenLines>=requiredLines||HeldLines==0){HeldLines=0;foreach(var f in Foes.Where(f=>f.Kind==YardBeast.Guardian))f.Stagger=1.85f;Say("Two pennants fly clear. The commander’s armor swings open.");}
            else Say($"{b.Skipper} is clear. Take the next line.");return true;
        }
        return false;
    }
    void Finish(MusterBoat b){b.Ready=true;b.LeftDock=Clock;Silver+=3;Active=-1;Say($"{b.Name} is ready. {b.Skipper} brings the crew and fittings to the gate.");}
    bool Near(Vector2 target,float reach)=>Vector2.DistanceSquared(Player,target)<=reach*reach;
    public void Say(string line){Line=line;LineTime=Math.Clamp(line.Length/15f,3,10);}
    static Vector2 Unit(Vector2 v)=>v.LengthSquared()>.001f?Vector2.Normalize(v):Vector2.UnitY;
    static float Cool(float v,float dt)=>Math.Max(0,v-dt);
}
