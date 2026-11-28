using System.Numerics;

namespace BoatsNBeasts.Core;

public enum PatrolRole { Pursuit, Flanker, Mortar, Caller }

public sealed partial class Voyage
{
    public void Grapple(Enemy enemy)
    {
        if (enemy.Health <= 0) return;
        bool interrupt = enemy.Telegraph > 0 || enemy.Fuse > 0 || enemy.Dash > 0 || enemy.AttackClock < 1.1f;
        enemy.Stunned = interrupt ? 2.7f : 1.2f;
        enemy.AttackClock = Math.Max(enemy.AttackClock, 2);
        enemy.Telegraph = enemy.Fuse = enemy.Dash = 0;
        enemy.Position = World.Slide(enemy.Position, enemy.Position + OceanWorld.Unit(Position - enemy.Position) * (enemy.Marked ? 18 : 70), enemy.Radius);
        Events.Add(new("pull", Position, 2, enemy.Position));
        Hit(enemy, interrupt ? 19 : 8);
    }

    public Enemy? DropPatrol(EnemyKind kind, Vector2 at, float strength, bool marked)
    {
        if (!Spawn(kind)) return null;
        var e = Enemies[^1];
        if (World.IsWater(at, e.Radius)) e.Position = at;
        e.Marked = marked;
        e.Health = e.MaxHealth = (marked ? 120 : e.MaxHealth) * strength;
        if (marked) e.SpeedMultiplier *= .80f;
        return e;
    }

    public void Lob(Vector2 origin,Vector2 target,float damage,float radius,float flight=1.55f)
    {
        if(Shots.Count>=320)return;
        Shots.Add(new(){Hostile=true,Position=origin,Previous=origin,Target=target,Velocity=(target-origin)/flight,
            FlightDuration=flight,Life=flight,Damage=damage,Radius=radius});
    }

    void WorkFormation(Enemy enemy,float dt,Vector2 dir,float distance,ref Vector2 motion,ref float speed)
    {
        if(enemy.Time < 1 || enemy.Dash>0 || enemy.Telegraph>0 || enemy.Fuse>0)return;
        enemy.RoleClock -= dt;
        var side = new Vector2(-dir.Y,dir.X) * (enemy.Id%2==0?1:-1);
        switch(enemy.Role)
        {
            case PatrolRole.Flanker:
                motion = distance>145 ? OceanWorld.Unit(dir*.52f+side*(distance>380?.48f:1.08f)) : dir;
                speed *= 1.25f;
                break;
            case PatrolRole.Mortar:
                motion = OceanWorld.Unit(dir*(distance>480?1:distance<285?-.85f:0)+side*.36f);
                if(distance<610 && enemy.RoleClock<=0)
                {
                    Lob(enemy.Position,Position+Velocity*.32f,11,92);
                    enemy.RoleClock=5.7f;
                }
                break;
            case PatrolRole.Caller:
                motion = OceanWorld.Unit(dir*(distance>375?.63f:distance<180?-.85f:.05f)+side*.47f);
                if(enemy.RoleClock<=0)
                {
                    var ward = Enemies.Where(e=>e!=enemy && !e.Marked && e.Health>0 && e.Health<e.MaxHealth &&
                        Vector2.DistanceSquared(e.Position,enemy.Position)<310*310).MinBy(e=>e.Health/e.MaxHealth);
                    if(ward!=null)
                    {
                        ward.Health=Math.Min(ward.MaxHealth,ward.Health+14);
                        Events.Add(new("arc",enemy.Position,0,ward.Position));
                    }
                    enemy.RoleClock=5;
                }
                break;
        }
    }

    public void Rake(Enemy enemy)
    {
        enemy.Stunned=2.5f;
        Events.Add(new("arc",Position,2,enemy.Position));
        Hit(enemy,35+Level*2);
    }

    public void HullHit(float damage) => DamagePlayer(damage);
    public void Patch(float health) => Heal(health);
}
