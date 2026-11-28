using System.Numerics;

namespace BoatsNBeasts.Core;

public enum UnderTrial { Mouth, Watch, Mirrors, Freight, Rescue, Capstan, Chart, Cradle, Camp, Stores, Keeper, Drain, Rail, Dig, Assay }
public enum UnderGate { Open, Staff, Toll, Seal, Service }
public sealed class UnderRoom(int id,int x,int y,UnderTrial trial,int reward,int seed)
{
    public readonly int Id=id,X=x,Y=y,Reward=reward,Seed=seed;
    public readonly UnderTrial Trial=trial;
    public bool Visited, Cleared,Initialized,Gift,Clue;
    public int Step,Read;
    public int[] Code=[0,1,2];
    public readonly bool[] Lit=new bool[3];
    public Vector2 Cargo,Escort;public bool Leads;
    public readonly List<YardBeastState> Foes=[];
    public readonly List<Vector2> Drops=[];
    public UnderBoard? Board;
    public DrainageBoard? Pipes;public SwitchRail? Rail;public AssayBalance? Balance;public TornChart? Mosaic;
}
public sealed class UnderDoor(int a,int b,UnderGate gate)
{
    public readonly int A=a,B=b;public readonly UnderGate Gate=gate;public bool Opened;
    public int Other(int i)=>A==i?B:A;
}
public sealed class Underfloor
{
    public readonly UnderRoom[] Rooms;
    public readonly UnderDoor[] Doors;
    public readonly int Seed;
    readonly UnderProfile biome;
    public Underfloor(CampaignOrder order,int runSeed,int floor)
    {
        uint hash=2166136261;foreach(char c in order.Id) hash=unchecked((hash^c)*16777619);
        Seed=unchecked((int)SeedRandom.Hash((uint)runSeed,floor,order.Tier,hash));var rng=new Random(Seed);biome=UnderProfile.For(order);
        int shape=(rng.Next(3)+floor+order.Tier)%3;
        (int x,int y)[] xy=shape switch{
            0=>[(1,3),(0,3),(2,3),(0,2),(1,2),(2,2),(3,2),(0,1),(1,1),(2,1),(3,1),(0,0),(1,0),(2,0),(3,0),(4,2),(4,1),(4,0)],
            1=>[(1,3),(0,3),(2,3),(0,2),(1,2),(2,2),(3,2),(0,1),(1,1),(2,1),(3,1),(0,0),(1,0),(2,0),(4,1),(3,3),(4,3),(4,2)],
            _=>[(2,3),(1,3),(3,3),(1,2),(2,2),(3,2),(0,2),(1,1),(2,1),(3,1),(4,2),(0,1),(2,0),(4,1),(0,0),(4,0),(1,0),(3,0)]
        };
        UnderTrial[] jobs=[UnderTrial.Mirrors,UnderTrial.Freight,UnderTrial.Rescue,UnderTrial.Capstan,UnderTrial.Chart,UnderTrial.Cradle];
        int offset=((int)LandingRegion.From(order.Region).Climate+floor)%jobs.Length;
        jobs=[..jobs.Skip(offset),..jobs.Take(offset)];if(rng.Next(2)==1)(jobs[0],jobs[2])=(jobs[2],jobs[0]);
        UnderTrial[] activities=[UnderTrial.Mouth,jobs[0],jobs[1],UnderTrial.Watch,UnderTrial.Camp,UnderTrial.Watch,UnderTrial.Stores,jobs[2],UnderTrial.Chart,jobs[3],UnderTrial.Stores,jobs[4],UnderTrial.Keeper,jobs[5],UnderTrial.Drain,UnderTrial.Rail,UnderTrial.Dig,UnderTrial.Assay];
        bool reflect=rng.Next(2)==1;int turn=rng.Next(4);
        Rooms=xy.Select((site,i)=>{
            int x=reflect?4-site.x:site.x,y=site.y;for(int k=0;k<turn;k++)(x,y)=(4-y,x);
            int reward=i is 1 or 2?1:i is 7 or 11?2:i is 9 or 13?3:0;
            var r=new UnderRoom(i,x,y,activities[i],reward,rng.Next());
            var code=new[]{0,1,2};rng.Shuffle(code);r.Code=code;return r;
        }).ToArray();
        var doors=new List<UnderDoor>();
        foreach(var a in Rooms)foreach(var b in Rooms)
        {
            if(b.Id<=a.Id||Math.Abs(a.X-b.X)+Math.Abs(a.Y-b.Y)!=1)continue;
            var gate=a.Id==12||b.Id==12?UnderGate.Seal:a.Id<16&&b.Id>=16?UnderGate.Service:
                a.Id<7&&b.Id>=7?UnderGate.Staff:a.Id==0&&b.Id==4?UnderGate.Toll:UnderGate.Open;
            doors.Add(new(a.Id,b.Id,gate));
        }
        var shafts=doors.Where(d=>d.Gate==UnderGate.Open&&d.A!=0&&d.B<16&&d.A>2).ToArray();
        rng.Shuffle(shafts);
        foreach(var shaft in shafts.Take(3))
        {
            doors.Remove(shaft);
            if(!Reachable(doors,UnderGate.Open,1,2)||!Reachable(doors,UnderGate.Staff,7,9,11,13,14,15)
                ||!Reachable(doors,UnderGate.Service,16,17))doors.Add(shaft);
        }
        Doors=doors.ToArray();
    }
    static bool Reachable(List<UnderDoor> doors,UnderGate access,params int[] goals)
    {
        HashSet<int> reached=[0];var q=new Queue<int>();q.Enqueue(0);
        while(q.TryDequeue(out var id))foreach(var d in doors)
        {
            if(d.A!=id&&d.B!=id||d.Gate==UnderGate.Seal||d.Gate==UnderGate.Toll
                ||d.Gate==UnderGate.Service&&access!=UnderGate.Service||d.Gate==UnderGate.Staff&&access==UnderGate.Open)continue;
            int next=d.Other(id);if(reached.Add(next))q.Enqueue(next);
        }
        return goals.All(reached.Contains);
    }
    public IEnumerable<UnderDoor> Exits(int here)=>Doors.Where(d=>d.A==here||d.B==here);
    public Vector2 Threshold(int here,UnderDoor door)
    {
        var a=Rooms[here];var b=Rooms[door.Other(here)];return new((b.X-a.X)*4.20f,(b.Y-a.Y)*3.05f);
    }
    public string Name(UnderRoom r)=>r.Trial switch{
        UnderTrial.Drain=>"The pressure orchard",UnderTrial.Rail=>"Parcel exchange",UnderTrial.Dig=>"Submerged cache",UnderTrial.Assay=>"Assay office",
        UnderTrial.Mouth=>"Ferry stair",UnderTrial.Watch=>r.Id==3?"West guard post":"East guard post",UnderTrial.Camp=>"Mess and archive",
        UnderTrial.Stores=>r.Id==6?"Shipwright’s locker":"Supper hatch",UnderTrial.Keeper=>biome.Sanctum,
        UnderTrial.Freight=>biome.Freight,UnderTrial.Mirrors=>biome.Light,UnderTrial.Capstan=>biome.Hoist,UnderTrial.Rescue=>biome.Shelter,
        UnderTrial.Cradle=>biome.Channel,_=>r.Id==8?"Pilots’ crossing":biome.Record
    };
}
public sealed record UnderProfile(string Freight,string Light,string Hoist,string Shelter,string Channel,string Record,string Sanctum,string[] Marks)
{
    public static UnderProfile For(CampaignOrder o)
    {
        var r=LandingRegion.From(o.Region);return new(r.WorkNames?[2]??r.Pin+" shop",r.Marks[0]+" lanterns",r.WorkNames?[4]??r.Lock,r.WorkNames?[3]??"Refuge for the "+r.Castaway,
            r.WorkNames?[1]??r.Cargo+" berth",r.Tally,"Lower "+r.Districts[^1],r.Marks);
    }
}
