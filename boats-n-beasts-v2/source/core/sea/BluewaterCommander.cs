using System.Numerics;

namespace BoatsNBeasts.Core;

public readonly record struct SeaThreat(Vector2 Start,Vector2 End,float Radius,float Eye=0)
{
    public bool Covers(Vector2 p)
    {
        var ray=End-Start;
        float along=Math.Clamp(Vector2.Dot(p-Start,ray)/Math.Max(1,ray.LengthSquared()),0,1);
        float d=Vector2.Distance(p,Start+ray*along);
        return d<Radius && (Eye<=0 || d>Eye);
    }
}

public sealed partial class BluewaterCourse
{
    public float Tell { get; private set; }
    public float WarningProgress => 1-Math.Clamp(Tell/1.65f,0,1);
    public IReadOnlyList<SeaThreat> Threats => threats;
    public string AttackName {get;private set;}="";
    readonly List<SeaThreat> threats=[];
    float nextAttack=2.8f;
    int beat;
    bool localMove;

    void CommanderAttack(float dt)
    {
        if(Captain==null)return;
        if(Captain.Stunned>0)
        {
            Tell=0;
            nextAttack=Math.Max(1.35f,nextAttack);
            return;
        }
        if(Tell>0)
        {
            Tell-=dt;
            if(Tell<=0)ResolveThreat();
            return;
        }
        nextAttack-=dt;
        if(nextAttack>0)return;
        localMove=beat++%2==0;
        if(Order.Duty==SeaDuty.Hunt && !localMove){nextAttack=2.3f;return;}
        Tell=1.65f;
        threats.Clear();
        var from=Captain.Position;
        var aim=Ship.Position+Ship.Velocity*.32f;
        var dir=OceanWorld.Unit(aim-from,course);
        var side=new Vector2(-dir.Y,dir.X);
        if(!localMove)
        {
            if(Order.Duty==SeaDuty.Convoy)
            {
                AttackName="Fire on the tow";
                var target=fleet.Count==0?aim:fleet[^1].Position;
                threats.Add(new(target,target,150));
            }
            else if(Order.Duty==SeaDuty.Sounding)
            {
                AttackName="Tuning strike";
                threats.Add(new(from,from,335,133));
            }
            else
            {
                AttackName=Order.Duty==SeaDuty.Salvage?"Dragnet":"Command broadside";
                threats.Add(new(from,from+dir*730,97));
            }
            return;
        }
        switch(Country.Climate)
        {
            case SeaClimate.Cinder:
                AttackName="Three furnace mouths";
                for(int i=-1;i<=1;i++)
                {
                    var fan=Vector2.TransformNormal(dir,Matrix3x2.CreateRotation(i*.48f));
                    threats.Add(new(from+fan*95,from+fan*590,58));
                }
                break;
            case SeaClimate.Delta:
                AttackName="Crossed millraces";
                threats.Add(new(aim-side*250-dir*110,aim+side*245+dir*30,65));
                threats.Add(new(aim-side*245+dir*168,aim+side*250+dir*308,65));
                break;
            case SeaClimate.Orchard:
                AttackName="Falling lantern fruit";
                for(int i=0;i<3;i++)
                {
                    var fruit=aim-dir*(i*130)+side*(i%2==0?45:-55);
                    threats.Add(new(fruit,fruit,92));
                }
                break;
            case SeaClimate.Shelf:
                AttackName="Pressure ridge";
                threats.Add(new(aim-side*320,aim+side*320,82));
                break;
            case SeaClimate.Loom:
                AttackName="Crossed sheets";
                threats.Add(new(from-side*235,from+dir*585+side*235,64));
                threats.Add(new(from+side*235,from+dir*585-side*235,64));
                break;
            case SeaClimate.Choir:
                AttackName="Reef overtone";
                threats.Add(new(from,from,292,163));
                threats.Add(new(from,from,491,398));
                break;
            case SeaClimate.Court:
                AttackName="Inspection lanterns";
                for(int i=-1;i<=1;i+=2)
                {
                    var spot=aim+side*(i*93);
                    threats.Add(new(spot,spot,122));
                }
                break;
            default:
                AttackName="Split star";
                for(int i=0;i<3;i++)
                {
                    var spike=Vector2.TransformNormal(dir,Matrix3x2.CreateRotation(i*MathF.Tau/3));
                    threats.Add(new(aim+spike*85,aim+spike*350,63));
                }
                break;
        }
    }

    void ResolveThreat()
    {
        foreach(var threat in threats)
            Ship.Events.Add(Vector2.DistanceSquared(threat.Start,threat.End)<1?
                new("bossExplosion",threat.Start,threat.Radius):new("arc",threat.Start,0,threat.End));
        bool hit=threats.Any(zone=>zone.Covers(Ship.Position));
        if(hit && !Ship.IsBoosting)
        {
            Ship.HullHit(12+Order.Tier);
            if(localMove)
            {
                switch(Country.Climate)
                {
                    case SeaClimate.Delta:
                    case SeaClimate.Loom:
                        Ship.Velocity+=OceanWorld.Unit(Captain!.Position-Ship.Position)*185;
                        Ship.Boost=Math.Max(0,Ship.Boost-18);
                        break;
                    case SeaClimate.Shelf:
                        Ship.Boost=Math.Max(0,Ship.Boost-32);
                        break;
                    case SeaClimate.Orchard:
                    case SeaClimate.Court:
                        if(Ship.Enemies.Count<8)AddRaider(Ship.Position+course*445,beat);
                        break;
                }
            }
            else if(Order.Duty==SeaDuty.Salvage)
                Ship.Position=Ship.World.Slide(Ship.Position,Ship.Position+OceanWorld.Unit(Captain!.Position-Ship.Position)*111,40);
        }
        foreach(var craft in fleet)
        {
            if(craft.HitCooldown>0 || !threats.Any(t=>t.Covers(craft.Position)))continue;
            craft.Health=Math.Max(0,craft.Health-9-Order.Tier);
            craft.HitCooldown=2.8f;
            if(craft.Health==0){Phase=ChartPhase.Lost;Say("Lio    The last line's parted! Take that crew off!");}
        }
        nextAttack= Math.Max(2.55f,4.8f-Order.Tier*.19f);
    }
}
