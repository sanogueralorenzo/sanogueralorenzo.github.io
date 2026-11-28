using System.Numerics;

namespace BoatsNBeasts.Core;

public enum UnderGift { Edge, Reel, Bread, Powder, Lamp, Boots }
public sealed partial class UnderwayRun
{
    public readonly CampaignOrder Order;public readonly Loadout Outfit;public readonly UnderProfile Biome;
    public readonly int Seed, Floors;
    public Underfloor Floor {get;private set;}=null!;
    public int Depth{get;private set;} public int Here{get;private set;} public UnderRoom Room=>Floor.Rooms[Here];
    int silver;public int Silver=>silver+(Surface?.Silver??0); public int Chits{get;private set;} public int Powder{get;private set;}=2;
    public int Rations{get;private set;} public int Vitality{get;private set;} public int Maximum{get;private set;}
    public int Edge{get;private set;}public int Reel{get;private set;} public int Boots{get;private set;} public int Lamps{get;private set;}
    public int Finds{get;private set;} public int RoomsDone{get;private set;} public bool Staff{get;private set;}
    public bool Lost=>Vitality<=0;public bool Won{get;private set;}public bool Extracting{get;private set;}
    public bool ChartOpen;public float Clock,Swing,Hook,HookWait,DodgeWait,Dash,Hurt,MessageClock,Flash;
    public Vector2 Player,Heading=-Vector2.UnitY,Mate,Vara,HookEnd; public string Message="";
    public readonly List<YardAttack> Attacks=[];
    public readonly List<string> Journal=[];
    public int EntryFrom{get;private set;}=-1;
    public int Keys=>Floor.Rooms.Count(r=>r.Cleared&&r.Reward>=2);
    public bool BothWards=>Floor.Rooms.Any(r=>r.Cleared&&r.Reward==2)&&Floor.Rooms.Any(r=>r.Cleared&&r.Reward==3);
    public int SealCost=>Depth==0?2:3;
    public bool WardsReady=>SealsReady&&ProofFiled;
    public float HookRange=>3.6f+.30f*Reel+(Outfit==Loadout.Longline?.85f:0);
    public Vector2 WardDesk=>new(-2.85f,-1.66f);
    public Vector2 FittingBench=>new(2.42f,.87f);
    public Vector2 Winch=>new(0,-2.05f);
    public bool Quiet=>Room.Foes.Count==0;
    float cutWait,safe;Vector2 dashDirection;
    public UnderwayRun(CampaignOrder order,int seed,int stores,Loadout outfit=Loadout.Standard)
    {
        Order=order;Seed=seed;Outfit=outfit;Biome=UnderProfile.For(order);
        Floors=Math.Max(1,order.Legs);Maximum=Vitality=12+Math.Clamp(stores,0,2)*2+(outfit==Loadout.Lifeboat?3:0);
        Rations=2+Math.Clamp(stores,0,2);LoadFloor();
    }
    void LoadFloor()
    {
        Floor=new(Order,Seed,Depth);Staff=false;Here=0;EntryFrom=-1;Attacks.Clear();Extracting=false;Enter(0,-1);
        Say(Depth==0?Order.Brief:$"Below the {RegionDistrict()}. The freight gate takes {SealCost} seals, including a brass and a blue one.");
    }
    public string RegionDistrict()
    {
        var names=LandingRegion.From(Order.Region).Districts;return names[(Depth+(int)((uint)Floor.Seed%(uint)names.Length))%names.Length];
    }
    public bool CanOpen(UnderDoor door)=>door.Opened||door.Gate switch{UnderGate.Staff=>Staff,UnderGate.Toll=>Here==4||Powder>0,UnderGate.Seal=>WardsReady,UnderGate.Service=>GalleryOpen,_=>true};
    public string DoorRule(UnderDoor d)=>d.Opened?"":d.Gate switch{
        UnderGate.Staff when !Staff=>" · staff key",UnderGate.Toll when Here!=4=>" · 1 powder",UnderGate.Seal when SealsReady&&!ProofFiled=>" · assay",UnderGate.Seal when !WardsReady=>$" · {Keys}/{SealCost} seals",UnderGate.Service when !GalleryOpen=>" · service lock",_=>""};
    public bool Seen(UnderRoom room)=>Lamps>0||room.Visited||Floor.Exits(room.Id).Any(d=>Floor.Rooms[d.Other(room.Id)].Visited);
    public string RewardName(UnderRoom room)=>room.Reward switch{1=>"staff key",2=>"brass seal",3=>"blue seal",_=>room.Trial==UnderTrial.Stores?"stores":room.Trial==UnderTrial.Camp?"fittings":""};
    public static Vector2 Walkable(Vector2 p)=>Vector2.Clamp(p,new(-4.33f,-3.18f),new(4.33f,3.18f));
    void Enter(int id,int previous)
    {
        Here=id;EntryFrom=previous;Attacks.Clear();Dash=Hook=Swing=0;
        var entering=Floor.Exits(id).FirstOrDefault(d=>d.Other(id)==previous);
        Player=entering==null?new(0,2.55f):Floor.Threshold(id,entering)*.83f;
        Heading=Unit(-Player);Mate=Walkable(Player+new Vector2(.50f,.15f));Vara=Walkable(Player-new Vector2(.46f,.25f));
        var r=Room;r.Visited=true;
        if(!r.Initialized){r.Initialized=true;SetTrial(r);}
        if(previous>=0)Say(r.Cleared?Floor.Name(r)+" is clear.":Hint);
    }
    void SetTrial(UnderRoom r)
    {
        if(r.Trial is UnderTrial.Mouth or UnderTrial.Camp or UnderTrial.Stores){r.Cleared=true;return;}
        if(r.Trial==UnderTrial.Rail)r.Rail=new(r.Seed,Depth);
        if(r.Trial==UnderTrial.Drain)r.Pipes=new(r.Seed);
        if(r.Trial==UnderTrial.Assay){if(Depth%2==1)r.Mosaic=new(r.Seed,Depth);else r.Balance=new(r.Seed,Depth);}
        if(r.Trial is UnderTrial.Mirrors or UnderTrial.Freight)r.Board=new(r.Seed,r.Trial==UnderTrial.Mirrors);
        r.Escort=Pad(r.Code[0]);r.Cargo=Pad(r.Code[1]);
        int count=r.Trial switch{UnderTrial.Watch=>2+Depth%2,UnderTrial.Keeper=>1,_=>0};
        for(int k=0;k<count;k++)AddFoe(k,r.Trial==UnderTrial.Keeper);
    }
    public Vector2 Pad(int i)
    {
        Vector2[] p=[new(-2.25f,-1.34f),new(2.20f,-1.28f),new(.18f,1.69f)];
        var at=p[i%3];return (Room.Seed&1)==0?at:new(-at.X,at.Y);
    }
    public string Mark(int i)=>Biome.Marks[i%Biome.Marks.Length];
    public void Say(string line){Message=line;MessageClock=Math.Clamp(line.Length/15f,3.4f,10.8f);}
    void Log(string line){Journal.Add($"Deck {Depth+1} · {line}");}
    void Clear()
    {
        if(Room.Cleared)return;Room.Cleared=true;RoomsDone++;Chits+=Room.Trial==UnderTrial.Watch?2:1;
        int pay=Room.Trial==UnderTrial.Keeper?5:2;silver+=pay;
        if(Room.Reward==1)Staff=true;
        var prize=RewardName(Room);if(prize.Length>0){Log(Floor.Name(Room)+" yielded a "+prize+".");Say($"{prize} secured. The crew salvaged {pay} silver. Open the chart to choose your next room.");}
        else Say(Room.Trial==UnderTrial.Watch?"The watch post is clear. The crew divides two work chits.":"The crew files the chamber’s receipt.");
    }
    public void Interact()
    {
        if(Surface!=null||Lost||Won||ChartOpen)return;
        if(Room.Trial==UnderTrial.Keeper&&Extracting&&Near(Winch,1.18f))
        {
            if(Depth+1==Floors){Won=true;return;}
            if(AtSurfaceLift){LaunchSurface(false);return;}
            Depth++;LoadFloor();return;
        }
        if(Operate())return;
        var door=Floor.Exits(Here).MinBy(d=>Vector2.DistanceSquared(Player,Floor.Threshold(Here,d)));
        if(door==null||!Near(Floor.Threshold(Here,door),.83f))return;
        if(!Quiet&&door.Other(Here)!=EntryFrom){Say("The watch has the far doors. The door you entered remains open.");return;}
        if(!CanOpen(door)){Say(door.Gate==UnderGate.Service||door.Gate==UnderGate.Seal&&SealsReady&&!ProofFiled?FieldHint:door.Gate==UnderGate.Seal?$"The lift needs {SealCost} seals, with both brass and blue represented. The marked side chambers hold alternatives.":door.Gate==UnderGate.Staff?"A staff key opens the upper galleries. Work either chamber beside the ferry stair.":"The boarded hatch needs one powder charge. The side doors are open.");return;}
        if(door.Gate==UnderGate.Toll&&!door.Opened&&Here!=4)Powder--;
        door.Opened=true;int previous=Here;Enter(door.Other(Here),previous);
    }
    public bool AtBench=>Room.Trial is UnderTrial.Stores or UnderTrial.Camp&&Near(FittingBench,1.30f);
    public void Choose(int option)
    {
        if(Surface!=null||Lost||Won||ChartOpen||option is <1 or >3)return;
        if(AtSurfaceLift&&Near(Winch,1.18f)&&option==2){LaunchSurface(true);return;}
        if(AtBench)
        {
            if(Room.Gift){Say("This bench has already supplied your crew.");return;}
            int price=Room.Trial==UnderTrial.Camp?2:0;
            if(Chits<price){Say("A fitting costs two work chits. Clear another chamber.");return;}
            var gift=Offers()[option-1];Chits-=price;Room.Gift=true;Apply(gift);return;
        }
        if(option==1)Eat();
    }
    public UnderGift[] Offers()
    {
        if(Room.Trial==UnderTrial.Camp)return Depth%2==0?[UnderGift.Edge,UnderGift.Reel,UnderGift.Bread]:[UnderGift.Boots,UnderGift.Powder,UnderGift.Lamp];
        return Room.Id==6?[UnderGift.Edge,UnderGift.Lamp,UnderGift.Powder]:[UnderGift.Bread,UnderGift.Reel,UnderGift.Boots];
    }
    void Apply(UnderGift gift)
    {
        switch(gift)
        {
            case UnderGift.Edge:Edge=Math.Min(5,Edge+1);break;
            case UnderGift.Reel:Reel=Math.Min(5,Reel+1);break;
            case UnderGift.Bread:Rations+=2;break;
            case UnderGift.Powder:Powder+=2;break;
            case UnderGift.Lamp:Lamps++;break;
            default:Boots=Math.Min(4,Boots+1);break;
        }
        Log(GiftText(gift));Say(GiftText(gift));
    }
    public static string GiftText(UnderGift gift)=>gift switch{UnderGift.Edge=>"Tempered edge · +2 cut",UnderGift.Reel=>"Salvage reel · longer, faster hook",UnderGift.Bread=>"Two rations · 5 vitality each",UnderGift.Powder=>"Two charges · break barred hatches",UnderGift.Lamp=>"Chart lamp · scout floor and reveal hints",_=>"Rubber soles · faster dodge recovery"};
    void Eat(){if(Rations==0||Vitality==Maximum){Say(Rations==0?"The ration tin is empty.":"The crew is at full vitality.");return;}Rations--;Vitality=Math.Min(Maximum,Vitality+5);Say("A hot ration restores five vitality.");}
    public bool Call(Shipmate mate)
    {
        if(Surface!=null)return Surface.CallShipmate(mate);
        if(Lost||Won||ChartOpen)return false;
        switch(mate)
        {
            case Shipmate.Vara when Vitality<Maximum:
                Vitality=Math.Min(Maximum,Vitality+4);Say("Vara pours four measures from her brass thermos.");return true;
            case Shipmate.Lio:
                var caught=Room.Foes.Where(f=>f.Health>0&&Near(f.Position,6)).OrderBy(f=>Vector2.DistanceSquared(f.Position,Player)).Take(3).ToArray();
                foreach(var f in caught){f.Stagger=2.6f;f.Rush=0;f.Hit=.3f;Attacks.RemoveAll(a=>a.Source==f);}
                if(caught.Length>0)Say("Lio drops his spare net across the passage.");return caught.Length>0;
            case Shipmate.Nell:
                Attacks.Clear();safe=Math.Max(safe,4);Say("Nell sounds the quiet bell. Four beats to cross the room.");return true;
            default:return false;
        }
    }
    bool Near(Vector2 p,float radius)=>Vector2.DistanceSquared(Player,p)<=radius*radius;
    static Vector2 Unit(Vector2 v)=>v.LengthSquared()>.0001f?Vector2.Normalize(v):Vector2.UnitY;
    static float Cool(float n,float dt)=>Math.Max(0,n-dt);
}
