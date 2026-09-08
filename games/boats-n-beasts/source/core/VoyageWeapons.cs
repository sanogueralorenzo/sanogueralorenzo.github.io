using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed partial class Voyage
{
    public int BroadsideSalvos { get; private set; }
    public int MinesDropped { get; private set; }
    public int MinesExploded { get; private set; }
    public int CannonRicochets { get; private set; }
    public int HarpoonPulls { get; private set; }

    void UpdateWeapons(float dt, bool safe)
    {
        var forward = new Vector2(MathF.Sin(Heading), -MathF.Cos(Heading));
        var starboard = new Vector2(-forward.Y, forward.X);
        for (int w = 0; w < Weapons.Length; w++)
        {
            Cooldowns[w] = Math.Max(0, Cooldowns[w] - dt);
            int rank = Weapons[w];
            if (rank == 0 || Cooldowns[w] > 0 || safe || Shots.Count >= 360) continue;
            float range = w == 4 ? (130 + rank * 8) * Area : w == 5 ? 430 * Area : w == 3 ? 285 * Area : 570;
            var target = Enemies.Where(e => e.Health > 0 && Vector2.DistanceSquared(e.Position, Position) < range * range)
                .Where(e => w != 5 || Math.Abs(Vector2.Dot(OceanWorld.Unit(e.Position-Position),starboard)) > MathF.Cos(BroadsideHalfAngle))
                .OrderBy(e => Vector2.DistanceSquared(e.Position,Position)).FirstOrDefault();
            if (w == 2)
            {
                if (Velocity.Length() < Speed * .2f || Shots.Count(s => !s.Hostile && s.Kind == WeaponKind.Mine && s.Life > 0) >= 8) continue;
                var stern = Position - forward * 70;
                if (!World.IsWater(stern, 12)) continue;
                Shots.Add(new() { Kind = WeaponKind.Mine, Position = stern, Previous = stern, Damage = 38 * (1 + .4f*(rank-1)), Life = 10, Radius = (100+rank*9)*Area });
                MinesDropped++; Events.Add(new("mineDrop",stern));
            }
            else
            {
                if (target == null) continue;
                float damage = (w == 0 ? 15 : w == 1 ? 13 : w == 4 ? 7 : w == 5 ? 20 : 18) * (1 + .4f * (rank - 1));
                if (w == 5)
                {
                    for (int side = -1; side <= 1; side += 2)
                    {
                        var sideTarget=Enemies.Where(e=>e.Health>0 && Vector2.DistanceSquared(e.Position,Position)<range*range && Vector2.Dot(OceanWorld.Unit(e.Position-Position),starboard*side)>MathF.Cos(BroadsideHalfAngle))
                            .OrderBy(e=>Vector2.DistanceSquared(e.Position,Position)).FirstOrDefault();
                        var sideAim=sideTarget==null?starboard*side:OceanWorld.Unit(sideTarget.Position-Position);
                        for (int row = -1; row <= 1; row++)
                        {
                            var dir = OceanWorld.Unit(sideAim + forward * row * .04f);
                            var start = Position + starboard * side * 39 + forward * row * 23;
                            Shots.Add(new() { Kind = WeaponKind.Broadside, Position = start, Previous = start, Velocity = dir * 520, Damage = damage, Life = range / 520, Radius = 8 });
                        }
                        Events.Add(new("broadside",Position+starboard*side*40,0,Position+starboard*side*90));
                    }
                    BroadsideSalvos++;
                }
                else if (w == 4)
                {
                    Events.Add(new("aura", Position, range));
                    foreach (var e in Enemies) if (e.Health > 0 && Vector2.Distance(e.Position,Position) < range + e.Radius) Hit(e,damage);
                }
                else if (w == 3)
                {
                    Vector2 from = Position; var chain = new HashSet<int>(); Enemy? hit = target;
                    for (int i = 0; i < 2 + rank && hit != null; i++)
                    {
                        chain.Add(hit.Id); Events.Add(new("arc", from, 0, hit.Position)); Hit(hit, damage * (hit.Mark > 0 ? SoakedDamageMultiplier : 1));
                        from = hit.Position;
                        hit = Enemies.Where(e => e.Health > 0 && !chain.Contains(e.Id) && Vector2.DistanceSquared(e.Position,from) < MathF.Pow(180*Area,2)).OrderBy(e => Vector2.DistanceSquared(e.Position,from)).FirstOrDefault();
                    }
                }
                else
                {
                    var mount = Position + forward * 48;
                    var dir = OceanWorld.Unit(target.Position-mount);
                    int count = w == 0 && rank >= 3 ? 2 : 1;
                    for (int i=0;i<count;i++)
                    {
                        var start = mount + dir*24 + new Vector2(-dir.Y,dir.X)*(count==2?(i==0?-9:9):0);
                        Shots.Add(new() { Kind=(WeaponKind)w, Position=start, Previous=start, Velocity=dir*(w==1?580:650), Damage=damage, Life=w==0?2.4f:1.15f, Radius=6, Pierce=w==1?rank:0, Bounces=w==0?1+rank/2:0 });
                    }
                    Events.Add(new(w==0?"shot":"harpoon",mount));
                }
            }
            Cooldowns[w] = (w==0?.85f:w==1?1.3f:w==2?2.4f:w==4?.6f:w==5?1.65f:1.55f)
                / ((1+.1f*(rank-1))*(1+ReloadRank*.12f)*(Slipstream>0?1.65f:1));
        }
    }
    static float SegmentDistance(Vector2 p,Vector2 a,Vector2 b)
    {
        var v=b-a; float t=v.LengthSquared()>0?Math.Clamp(Vector2.Dot(p-a,v)/v.LengthSquared(),0,1):0;
        return Vector2.Distance(p,a+t*v);
    }
    void UpdateShots(float dt,bool safe,bool boosting)
    {
        foreach (var s in Shots)
        {
            if (s.Life<=0) continue;
            s.Previous=s.Position; s.Position+=s.Velocity*dt; s.Life-=dt; s.Age+=dt;
            if (s.Life<=0) continue;
            if (s.Hostile)
            {
                if (World.HarborAt(s.Position)!=null) { s.Life=0; continue; }
                if (SegmentDistance(Position,s.Previous,s.Position)<26+s.Radius) { if(!safe) DamagePlayer(s.Damage,boosting); s.Life=0; }
                if (!World.IsWater(s.Position,1)) s.Life=0;
                continue;
            }
            if (s.Kind==WeaponKind.Mine)
            {
                if (s.Life>0 && s.Age>=.5f && Enemies.Any(e=>e.Health>0 && Vector2.Distance(e.Position,s.Position)<55+e.Radius))
                {
                    s.Life=0; MinesExploded++; Events.Add(new("explosion",s.Position,s.Radius));
                    foreach(var e in Enemies) if(e.Health>0 && Vector2.Distance(e.Position,s.Position)<s.Radius+e.Radius) Hit(e,s.Damage*(e.Mark>0?SoakedDamageMultiplier:1));
                }
                continue;
            }
            var obstacle=World.Places.FirstOrDefault(p=>OceanWorld.IsSolid(p) && Vector2.Distance(p.Position,s.Position)<p.Radius+2);
            if(obstacle!=null)
            {
                if(s.Kind==WeaponKind.Cannon && s.Bounces>0)
                {
                    var normal=OceanWorld.Unit(s.Previous-obstacle.Position,Vector2.UnitX);
                    s.Velocity=Vector2.Reflect(s.Velocity,normal); s.Position=s.Previous+normal*3; s.Bounces--;
                    CannonRicochets++; Events.Add(new("ricochet",s.Position));
                }
                else s.Life=0;
                continue;
            }
            foreach(var e in Enemies)
            {
                if(e.Health<=0 || s.Hit.Contains(e.Id) || SegmentDistance(e.Position,s.Previous,s.Position)>e.Radius+s.Radius) continue;
                s.Hit.Add(e.Id); Hit(e,s.Damage*(s.Kind==WeaponKind.Broadside && e.Mark>0?SoakedDamageMultiplier:1));
                if(s.Kind==WeaponKind.Harpoon && e.Health>0)
                {
                    e.Mark=4.5f+Weapons[1]*.3f; e.Pull=.4f; HarpoonPulls++; Events.Add(new("pull",Position,0,e.Position));
                }
                if(s.Kind==WeaponKind.Cannon && s.Bounces>0)
                {
                    var next=Enemies.Where(other=>other.Health>0 && !s.Hit.Contains(other.Id) && Vector2.DistanceSquared(other.Position,e.Position)<320*320).OrderBy(other=>Vector2.DistanceSquared(other.Position,e.Position)).FirstOrDefault();
                    s.Position=e.Position;
                    s.Velocity=next!=null?OceanWorld.Unit(next.Position-e.Position)*650:-s.Velocity;
                    s.Bounces--; CannonRicochets++; Events.Add(new("ricochet",s.Position)); break;
                }
                if(s.Pierce--<=0) { s.Life=0; break; }
            }
        }
    }
}
