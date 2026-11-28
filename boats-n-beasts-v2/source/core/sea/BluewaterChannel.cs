using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed class ChannelBank(Vector2 center,Vector2 axis,float halfSpan,float width,bool breakable,float sway)
{
    public Vector2 Position = center;
    public readonly Vector2 Mooring = center, Axis = axis;
    public readonly float HalfSpan = halfSpan, Width = width, Sway = sway;
    public readonly bool Breakable = breakable;
    public bool Broken;
    public int Hits;
    public Vector2 Shackle => Position + Axis * HalfSpan * .75f;
    public Vector2 Closest(Vector2 p) => Position + Axis * Math.Clamp(Vector2.Dot(p - Position,Axis),-HalfSpan,HalfSpan);
    public Vector2 Slide(Vector2 p,float clearance)
    {
        var nearest=Closest(p);
        var offset=p-nearest;
        float reach=Width+clearance;
        if(offset.LengthSquared()>=reach*reach)return p;
        return nearest+OceanWorld.Unit(offset,new(-Axis.Y,Axis.X))*reach;
    }
}

public sealed partial class BluewaterCourse
{
    public IReadOnlyList<ChannelBank> Banks=>banks;
    public int ChannelRevision {get;private set;}
    readonly List<ChannelBank> banks=[];
    float swell;
    int islandPattern;
    public Enemy? Tether {get;private set;}
    public float RopeLeft {get;private set;}
    public bool SeamReady {get;private set;}
    Vector2 setBearing;

    void LayBanks()
    {
        banks.Clear();
        ChannelRevision++;
        var forward=OceanWorld.Unit(Target-Ship.Position,course);
        var side=new Vector2(-forward.Y,forward.X);
        var climate=Country.Climate;
        bool floating=climate is SeaClimate.Delta or SeaClimate.Shelf or SeaClimate.Loom or SeaClimate.Court or SeaClimate.Bottle or SeaClimate.Wax or SeaClimate.Sleep or SeaClimate.Calving;
        int rows=Order.Tier>=5 || RedPassage ? 3 : 2;
        for(int row=0;row<rows;row++)
        {
            float fraction=(row+1f)/(rows+1);
            var center=Vector2.Lerp(Ship.Position,Target,fraction);
            pilot.Stream(center);
            int stagger=(row+islandPattern+Leg)%2==0?1:-1;
            for(int bank=-1;bank<=1;bank+=2)
            {
                float gap=climate switch {SeaClimate.Shelf or SeaClimate.Salt=>215,SeaClimate.Loom or SeaClimate.Pitch=>179,SeaClimate.Delta or SeaClimate.Drum=>205,SeaClimate.Calving=>290,_=>235};
                var p=center+side*(bank*gap+stagger*(65+islandPattern%65))+forward*(bank*stagger*78);
                if(!pilot.IsWater(p,130)||Vector2.DistanceSquared(p,Target)<315*315||
                    Crossing&&(Vector2.DistanceSquared(p,Shelter)<205*205||Vector2.DistanceSquared(p,Prize)<205*205))continue;
                float turn=(bank*stagger)*(.19f + islandPattern%7*.07f);
                var axis=Vector2.TransformNormal(forward,Matrix3x2.CreateRotation(turn));
                bool breaks=bank*stagger>0 || climate is SeaClimate.Shelf or SeaClimate.Loom or SeaClimate.Bottle or SeaClimate.Tin;
                banks.Add(new(p,axis,78 + (climate==SeaClimate.Loom ? 52 : islandPattern%38),
                    climate is SeaClimate.Shelf or SeaClimate.Sleep or SeaClimate.Calving ? 66 : 41,breaks,floating ? stagger*(22+BattleTier*2) : 0));
            }
        }
    }

    void TickBanks(float dt)
    {
        swell+=dt;
        for(int i=0;i<banks.Count;i++)
        {
            var bank=banks[i];
            if(bank.Broken)continue;
            var side=new Vector2(-bank.Axis.Y,bank.Axis.X);
            bank.Position=bank.Mooring+side*bank.Sway*MathF.Sin(swell*.77f+i*.91f);
            var pushed=bank.Slide(Ship.Position,32);
            if(pushed!=Ship.Position)Ship.Position=Ship.World.Slide(Ship.Position,pushed,29);
            foreach(var foe in Ship.Enemies)
                if(foe.Health>0 && Vector2.DistanceSquared(foe.Position,bank.Position)<360*360)
                    foe.Position=bank.Slide(foe.Position,foe.Radius*.72f);
            foreach(var shot in Ship.Shots)
            {
                if(shot.Hostile||shot.Life<=0||shot.Kind!=WeaponKind.Cannon)continue;
                if(Vector2.DistanceSquared(shot.Position,bank.Closest(shot.Position))>bank.Width*bank.Width)continue;
                shot.Life=0;
                if(bank.Breakable&&Vector2.DistanceSquared(shot.Position,bank.Shackle)<90*90)
                {
                    bank.Hits++;
                    if(bank.Hits>=2)
                    {
                        bank.Broken=true;
                        Ship.Events.Add(new("explosion",bank.Shackle,116));
                        foreach(var foe in Ship.Enemies)
                            if(foe.Health>0&&Vector2.DistanceSquared(foe.Position,bank.Shackle)<180*180)foe.Stunned=2.5f;
                        Purse++;
                    }
                    else Ship.Events.Add(new("ricochet",bank.Shackle));
                }
                break;
            }
        }
    }

    Vector2 FloatAroundBanks(Vector2 p)
    {
        foreach(var bank in banks)if(!bank.Broken)p=bank.Slide(p,22);
        return p;
    }

    void AttachLine(Enemy enemy)
    {
        Tether=enemy;
        RopeLeft=4.0f;
        SeamReady=false;
        setBearing=OceanWorld.Unit(Ship.Position-enemy.Position);
    }

    void WorkLine(float dt,SailInput input)
    {
        if(Tether==null)return;
        RopeLeft-=dt;
        var toShip=Ship.Position-Tether.Position;
        if(Tether.Health<=0 || RopeLeft<=0 || toShip.Length()>HookReach+140)
        {
            Tether=null;SeamReady=false;return;
        }
        var ray=OceanWorld.Unit(toShip);
        if(!SeamReady && Vector2.Dot(setBearing,ray)<.85f && toShip.Length()>100)
        {
            SeamReady=true;
            Say("Lio    She’s turned her soft side! Bring Vara’s guns across!");
        }
        if(!SeamReady || !Ship.Events.Any(e=>e.Kind=="shot"))return;
        var bow=new Vector2(MathF.Sin(Ship.Heading),-MathF.Cos(Ship.Heading));
        if(Math.Abs(Vector2.Dot(bow,ray))>.70f ||
            input.Aim is Vector2 aim && Vector2.DistanceSquared(aim,Tether.Position)>150*150)return;
        Ship.Rake(Tether);
        if(Tether==Captain)Tell=0;
        HookCooldown=Math.Max(0,HookCooldown-2);
        Ship.Boost=Math.Min(100,Ship.Boost+22);
        Tether=null;SeamReady=false;
        Say("Vara    A clean rake. Take the wind while she’s down!");
    }
}
