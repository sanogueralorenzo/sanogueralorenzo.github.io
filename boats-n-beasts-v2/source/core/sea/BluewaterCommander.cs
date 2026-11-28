using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed partial class BluewaterCourse
{
    public float Tell { get; private set; }
    public Vector2 AttackFrom { get; private set; }
    public Vector2 AttackTo { get; private set; }
    public float WarningProgress => 1 - Math.Clamp(Tell/1.55f,0,1);
    float nextAttack = 3.4f;

    void CommanderAttack(float dt)
    {
        if(Captain==null || Order.Duty==SeaDuty.Hunt) return;
        if(Captain.Stunned>0)
        {
            Tell=0;
            nextAttack=Math.Max(1.8f,nextAttack);
            return;
        }
        if(Tell>0)
        {
            Tell-=dt;
            if(Tell>0)return;
            bool hit;
            if(Order.Duty==SeaDuty.Convoy)
            {
                Ship.Events.Add(new("bossExplosion",AttackTo,151));
                hit=Vector2.DistanceSquared(Ship.Position,AttackTo)<151*151;
                foreach(var boat in fleet.Where(b=>Vector2.DistanceSquared(b.Position,AttackTo)<151*151 && b.HitCooldown<=0))
                {
                    boat.Health=Math.Max(0,boat.Health-12-Order.Tier);
                    boat.HitCooldown=2.8f;
                    if(boat.Health==0)Phase=ChartPhase.Lost;
                }
            }
            else if(Order.Duty==SeaDuty.Sounding)
            {
                Ship.Events.Add(new("bossExplosion",AttackFrom,310));
                float r=Vector2.Distance(Ship.Position,AttackFrom);
                hit=r is >=137 and <=310;
            }
            else
            {
                var line=AttackTo-AttackFrom;
                float along=Math.Clamp(Vector2.Dot(Ship.Position-AttackFrom,line)/Math.Max(1,line.LengthSquared()),0,1);
                hit=Vector2.DistanceSquared(Ship.Position,AttackFrom+line*along)<98*98;
                Ship.Events.Add(new("arc",AttackFrom,0,AttackTo));
                if(hit && Order.Duty==SeaDuty.Salvage && !Ship.IsBoosting)
                    Ship.Position=Ship.World.Slide(Ship.Position,Ship.Position+OceanWorld.Unit(AttackFrom-Ship.Position)*100,40);
            }
            if(hit && !Ship.IsBoosting)Ship.HullHit(12+Order.Tier);
            nextAttack=5.4f;
            return;
        }
        nextAttack-=dt;
        if(nextAttack>0)return;
        Tell=1.55f;
        AttackFrom=Captain.Position;
        var target=Order.Duty==SeaDuty.Convoy && fleet.Count>0 ? fleet[^1].Position : Ship.Position+Ship.Velocity*.3f;
        AttackTo=Order.Duty is SeaDuty.Blockade or SeaDuty.Salvage ? AttackFrom+OceanWorld.Unit(target-AttackFrom)*690 : target;
    }
}
