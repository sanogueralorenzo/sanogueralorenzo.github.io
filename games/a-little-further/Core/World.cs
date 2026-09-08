using System.Numerics;
namespace Further.Core;

public readonly record struct Cell(int X,int Z);
public sealed record Island(Cell Cell,Vector2 Center,float Radius,float Peak,int Biome,int Seed,string Name)
{
    public float Handedness=>Seed%2==0?1:-1;
    public Vector2 Landing
    {
        get
        {
            float a=-MathF.PI/2,phase=Seed%19;
            float outline=1+.07f*MathF.Sin(a*3+phase)+.035f*MathF.Sin(a*7+phase*.31f);
            return Center+new Vector2(0,-.96f*(outline*Radius-5.5f));
        }
    }
    public Vector2 InteriorPoint(float x,float z)=>new(Handedness*Radius*x*(.88f+(Seed%7)*.04f),Radius*(z*(.91f+(Seed%5)*.045f)+(Seed%3-1)*.035f));
    public Vector2 Shrine=>Center+InteriorPoint(.32f,.20f);
}
public sealed class World(int seed)
{
    // Placement cells identify islands; terrain tessellation is independent of this spacing.
    public const int ChunkSize=3200;
    public const float SightDistance=620;
    public int Seed{get;}=seed;
    public Cell Origin;
    public Cell CellAt(Vector2 p)=>new(Origin.X+(int)MathF.Floor((p.X+ChunkSize/2f)/ChunkSize),Origin.Z+(int)MathF.Floor((p.Y+ChunkSize/2f)/ChunkSize));
    public static uint Hash(int x,int z,int seed)
    {
        uint h=unchecked((uint)(x*374761393+z*668265263+seed*1442695041));
        h=(h^(h>>13))*1274126177;return h^(h>>16);
    }
    public Island IslandAt(Cell c)
    {
        int s=(int)(Hash(c.X,c.Z,Seed)&0x7fffffff);var r=new Random(s);bool home=c==new Cell(0,0);
        var center=new Vector2((c.X-Origin.X)*ChunkSize,(c.Z-Origin.Z)*ChunkSize)+(home?Vector2.Zero:new Vector2(r.Next(-140,141),r.Next(-140,141)));
        string[] first=["Copper","Whisper","Marigold","Gull","Juniper","Lantern","Coral","Morrow"];
        string[] last=["Cay","Reach","Hollow","Heights","Rest","Cove"];
        return new(c,center,home?97:r.Next(90,106),home?23:r.Next(18,31),home?0:r.Next(3),s,home?"Marigold Cay":$"{first[s%first.Length]} {last[s/9%last.Length]}");
    }
    public float Height(Vector2 p)=>Height(IslandAt(CellAt(p)),p);
    public static float Smooth(float a,float b,float x){float t=Math.Clamp((x-a)/(b-a),0,1);return t*t*(3-2*t);}
    public static float Height(Island island,Vector2 p)
    {
        var q=p-island.Center;float r=island.Radius;
        float angle=MathF.Atan2(q.Y,q.X),phase=island.Seed%19;
        float outline=1+.07f*MathF.Sin(angle*3+phase)+.035f*MathF.Sin(angle*7+phase*.31f);
        float d=new Vector2(q.X/1.10f,q.Y/.96f).Length()/r;
        float shore=(outline-d)*r;
        if(shore< -8)return -5;
        float noise=PrivateSources.Fractal(q.X+island.Seed%400,q.Y,4,2.05f,.48f,38);
        float Hill(Vector2 center,float width)=>MathF.Exp(-Vector2.DistanceSquared(q,center)/(width*width));
        float hills=island.Peak*Hill(island.InteriorPoint(.34f,.24f),r*(.34f+(island.Seed%4)*.035f))
            +island.Peak*(.34f+(island.Seed%3)*.18f)*Hill(island.InteriorPoint(-.52f,.38f),r*.25f)
            +island.Peak*(.18f+(island.Seed%5)*.065f)*Hill(island.InteriorPoint(-.52f,-.28f),r*.24f);
        // Broad coastal flats, two wooded hills, a saddle and a shallow inland hollow.
        float hollow=3.4f*Hill(new(-r*.13f,r*.14f),r*.23f);
        float inland=2.4f+hills-hollow+(noise-.85f)*2.1f;
        return -5+Smooth(-8,5,shore)*6.6f+Smooth(7,28,shore)*inland;
    }
    public bool InSight(Island island,Vector2 p)=>Vector2.Distance(island.Center,p)<SightDistance+island.Radius;
    public IEnumerable<Cell> Visible(Vector2 p,int radius=1)
    {
        Cell c=CellAt(p);
        return from z in Enumerable.Range(c.Z-radius,radius*2+1)
            from x in Enumerable.Range(c.X-radius,radius*2+1)
            orderby Vector2.DistanceSquared(new((x-Origin.X)*ChunkSize,(z-Origin.Z)*ChunkSize),p)
            select new Cell(x,z);
    }
}
