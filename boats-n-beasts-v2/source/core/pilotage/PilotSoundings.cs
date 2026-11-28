using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed record SurveyLight(string Name, Vector2 Position, int Shape);
public sealed record BearingFix(int Near, int Far, Vector2 Position, int FirstBearing, int SecondBearing);

public sealed class PilotSoundings
{
    public const float Reach = 350, Tolerance = 158;
    public static readonly Vector2 Bounds = new(6800,5300);
    public Voyage Ship { get; }
    public CampaignOrder Order { get; }
    public SurveyLight[] Lights { get; }
    public BearingFix[] Fixes { get; }
    public IReadOnlyList<Place> Coast { get; }
    public int Page { get; private set; }
    public bool Surveyed => Page >= Fixes.Length;
    public BearingFix Fix => Fixes[Math.Min(Page,Fixes.Length-1)];
    public bool SecondSight { get; private set; }
    public bool Won { get; private set; }
    public bool Lost => Ship.Mode == VoyageMode.Defeat;
    public int Silver { get; private set; }
    public int Kits { get; private set; }
    public Vector2? Pin { get; set; }
    public Vector2 Landing { get; }
    public float SoundCooldown { get; private set; }
    public string Report { get; private set; } = "Open the chart to read the pilot’s first bearing.";
    public float ReportLeft { get; private set; } = 6;
    public float LineCooldown { get; private set; }
    public int NearestLight => Array.FindIndex(Lights,light=>Vector2.Distance(light.Position,Ship.Position)<Reach);
    readonly Loadout outfit;
    readonly Random random;
    int bounty, patrols;
    float distance;
    bool[] visited;

    public PilotSoundings(CampaignOrder order,int seed,int stores,Loadout outfit=Loadout.Standard, BoatKind vessel = BoatKind.Cutter)
    {
        Order=order; this.outfit=outfit; random=new(seed);
        Ship=new((uint)seed,vessel,1){Charted=true,HullRank=Math.Clamp(stores,0,2)};
        Ship.Weapons[0]=Math.Max(1,Ship.Weapons[0]);
        Ship.Health=Ship.MaxHealth; Kits = outfit==Loadout.Lifeboat ? 3 : 1;
        var ocean=new OceanWorld((uint)seed);
        var edge=OceanWorld.KeyAt(Bounds);
        var islands=new Dictionary<string,Place>();
        for(int y=-edge.Y-1;y<=edge.Y+1;y++)
            for(int x=-edge.X-1;x<=edge.X+1;x++)
                foreach(var place in ocean.Generate(new(x,y)).Places.Where(OceanWorld.IsSolid))
                    islands.TryAdd(place.Id,place);
        Coast=islands.Values.ToArray();
        string[] names=["The Mitten","Split Spar","Kettle Rock","The Shuttle","Spoonbill","Twin Lamps","The Harp","Potter’s Wheel"];
        random.Shuffle(names);
        Lights=new SurveyLight[8];
        for(int i=0;i<Lights.Length;i++)
        {
            float x=(i%4-1.5f)*2920 + random.Next(-510,511);
            float y=(i/4==0?-1:1)*(2650+random.Next(-740,741));
            Lights[i]=new(names[i],Water(new(x,y),115),i);
        }
        var used=new List<Vector2>();
        Fixes=new BearingFix[3+Math.Min(2,order.Tier/3)];
        var farIndices=Enumerable.Range(0,8).ToArray();
        random.Shuffle(farIndices);
        for(int i=0;i<Fixes.Length;i++)
        {
            int far=farIndices[i], near=(far+2+random.Next(5))%8;
            var a=Lights[near].Position;
            var b=Lights[far].Position;
            Vector2 normal=Vector2.Normalize(new Vector2(b.Y-a.Y,a.X-b.X));
            BearingFix? FindFix(Vector2 guess)
            {
                var point=Water(Vector2.Clamp(guess,-Bounds*.90f,Bounds*.90f),175);
                int first=Bearing(a,point), second=Bearing(b,point);
                var u=Along(first); var v=Along(second);
                float angle=Cross(u,v);
                if(Math.Abs(angle)<.25f)return null;
                var crossing=a+u*(Cross(b-a,v)/angle);
                if(Vector2.Distance(crossing,point)>Tolerance*.65f || !Clear(crossing,145)
                    || used.Any(old=>Vector2.Distance(crossing,old)<820)
                    || Lights.Any(light=>Vector2.Distance(light.Position,crossing)<475))return null;
                return new(near,far,crossing,first,second);
            }
            BearingFix? fix=null;
            for(int n=0;n<28 && fix==null;n++)
            {
                var guess=Vector2.Lerp(a,b,.23f+random.NextSingle()*.54f)+normal*random.Next(740,2100)*(random.Next(2)==0?1:-1);
                fix=FindFix(guess);
            }
            for(int y=-4100;fix==null && y<=4100;y+=410)
                for(int x=-5700;fix==null && x<=5700;x+=410)fix=FindFix(new(x,y));
            Fixes[i]=fix ?? throw new InvalidOperationException("No crossing for the pilot lights.");
            used.Add(Fixes[i].Position);
        }
        visited=new bool[Lights.Length];
        Landing=Water(new(random.Next(-3700,3700),-4720),150);
    }
    Vector2 Water(Vector2 guess,int clearance)
    {

        for(int radius=0;radius<22;radius++)
            for(int j=0;j<(radius==0?1:16);j++)
            {
                float a=(j+.3f*radius)*MathF.Tau/16;
                var point=guess+new Vector2(MathF.Cos(a),MathF.Sin(a))*radius*95;
                if(Clear(point,clearance))return point;
            }
        return StartingArea.Spawn;
    }
    static float Cross(Vector2 a,Vector2 b) => a.X*b.Y-a.Y*b.X;
    bool Clear(Vector2 point,int clearance) => Math.Abs(point.X)<Bounds.X-180 && Math.Abs(point.Y)<Bounds.Y-180
        && Coast.All(place=> !OceanWorld.Overlap(place,point,clearance,out _,out _));
    public static int Bearing(Vector2 from,Vector2 to) =>
        ((int)MathF.Round(MathF.Atan2(to.X-from.X,from.Y-to.Y)*180/MathF.PI)+360)%360;
    public static Vector2 Along(int degrees)
    {
        float angle=degrees*MathF.PI/180;
        return new(MathF.Sin(angle),-MathF.Cos(angle));
    }
    public void Tick(float dt,SailInput helm)
    {
        if(Won || Ship.Mode!=VoyageMode.Sailing)return;
        SoundCooldown=Math.Max(0,SoundCooldown-dt); LineCooldown=Math.Max(0,LineCooldown-dt);
        ReportLeft=Math.Max(0,ReportLeft-dt);
        var before=Ship.Position;
        Ship.Tick(dt,helm);
        Ship.Position=Vector2.Clamp(Ship.Position,-Bounds,Bounds);
        distance+=Vector2.Distance(before,Ship.Position);
        if(distance>1150 && Ship.Enemies.Count<3+Order.Tier/2)
        {
            distance=0; patrols++;
            var kinds=new[]{EnemyKind.Crab, EnemyKind.Puffer, EnemyKind.Ray, EnemyKind.Serpent};
            Ship.Spawn(kinds[(patrols+Order.Tier)%4]);
        }
        if(Ship.Kills>=bounty+3) {bounty+=3;Silver+=2;}
    }
    public void Hail()
    {
        if(Won || Ship.Mode!=VoyageMode.Sailing || LineCooldown>0)return;
        if(Surveyed && Vector2.Distance(Ship.Position,Landing)<Reach)
        {Won=true;Silver+=8;return;}
        int near=NearestLight;
        if(near>=0)
        {
            if(!visited[near]){visited[near]=true;Silver+=2;Ship.Patch(8);}
            LineCooldown=.65f;
            if(!Surveyed && near==Fix.Far)
            {
                SecondSight=true;Say($"{Lights[near].Name} reports {Fix.SecondBearing:000}°. Plot where the two sights meet.");
            }
            else Say($"{Lights[near].Name} answers. The chart records this light.");
            return;
        }
        var foe=Ship.Enemies.Where(e=>e.Health>0 && Vector2.Distance(Ship.Position,e.Position)<(outfit==Loadout.Longline?665:490))
            .MinBy(e=>Vector2.DistanceSquared(Ship.Position,e.Position));
        if(foe!=null){Ship.Grapple(foe);LineCooldown=outfit==Loadout.Longline?3.8f:4.8f;}
        else Say(Surveyed?"Hail the island tender when alongside.":"Bring the ship beside a signal light to hail it.");
    }
    public void Sound()
    {
        if(Surveyed || Won || Ship.Mode!=VoyageMode.Sailing || SoundCooldown>0)return;
        SoundCooldown=2.4f;
        if(!SecondSight){Say("Hail the light for its bearing before filing a depth.");return;}
        float range=Vector2.Distance(Ship.Position,Fix.Position);
        if(range>Tolerance)
        {
            Say(range<520?"Pale sand on the lead. The channel is close.":"Hard shale on the lead. Try the crossing of the two bearings.");
            return;
        }
        Silver+=5;Page++;SecondSight=false;Pin=null;
        Say(Surveyed?"The last depth agrees. Hail the island tender to file the soundings.":"Good holding ground. The next lights are in the pilot book.");
    }
    public void Patch()
    {
        if(Kits==0 || Ship.Health>=Ship.MaxHealth || Ship.Mode!=VoyageMode.Sailing)return;
        Kits--;Ship.Patch(outfit==Loadout.Lifeboat?55:39);Say("Vara seals the planking around the lead well.");
    }
    public void Say(string line){Report=line;ReportLeft=4;}
}
