using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed partial class Voyage
{
    public int ArcaneCasts { get; private set; }
    public int MinesDropped { get; private set; }
    public int MinesExploded { get; private set; }
    public int CannonRicochets { get; private set; }
    public int HarpoonPulls { get; private set; }

    void UpdateWeapons(float dt)
    {
        var forward = Forward;
        for (int w = 0; w < Weapons.Length; w++)
        {
            Cooldowns[w] = Math.Max(0, Cooldowns[w] - dt * FireRateMultiplier);
            int rank = Weapons[w];
            if (rank == 0 || Cooldowns[w] > 0 || Shots.Count >= 360) continue;
            if (w == 2)
            {
                if (Velocity.Length() < Speed * .2f || Shots.Count(s => !s.Hostile && s.Kind == WeaponKind.Mine && s.Life > 0) >= 8) continue;
                var stern = Position - forward * 70;
                if (!World.IsWater(stern, 12)) continue;
                Shots.Add(new() { Kind = WeaponKind.Mine, Position = stern, Previous = stern, Damage = 38, Life = 10, Radius = (109+(rank-1)*30)*Area });
                MinesDropped++; Events.Add(new("mineDrop",stern));
            }
            else
            {
                var kind = (WeaponKind)w;
                bool deck = kind is WeaponKind.Cannon or WeaponKind.Harpoon;
                var origin = deck ? DeckPivot(kind) : Position;
                float range = kind == WeaponKind.Undertow ? WhirlpoolRadius : kind == WeaponKind.Coil ? 285 * Area : 570;
                var target = Enemies.Where(enemy => enemy.Health > 0 && !enemy.Emerging)
                    .Where(enemy =>
                    {
                        float reach = range + (kind == WeaponKind.Undertow ? enemy.Radius : 0);
                        return Vector2.DistanceSquared(enemy.Position, origin) <= reach * reach;
                    })
                    .OrderBy(enemy => Vector2.DistanceSquared(enemy.Position, origin))
                    .FirstOrDefault(enemy => kind == WeaponKind.Undertow || World.OpenShot(origin, enemy.Position));
                if (target == null)
                {
                    if (kind == WeaponKind.Cannon) CannonAim = Vector2.Zero;
                    if (kind == WeaponKind.Harpoon) HarpoonAim = Vector2.Zero;
                    continue;
                }
                float damage = w switch { 0 => 16, 1 => 17 + 4 * (rank - 1), 4 => 9 + 2 * (rank - 1), 5 => 24, _ => 17 + 2 * (rank - 1) };
                if (w == 5)
                {
                    var aim = OceanWorld.Unit(target.Position-Position);
                    for (int orb = 0; orb < rank; orb++)
                    {
                        float spread = (orb-(rank-1)/2f)*.3f;
                        var dir = new Vector2(aim.X*MathF.Cos(spread)-aim.Y*MathF.Sin(spread),aim.X*MathF.Sin(spread)+aim.Y*MathF.Cos(spread));
                        var start = Position + dir*55;
                        Shots.Add(new() { Kind=WeaponKind.Arcane, Position=start, Previous=start, Velocity=dir*400, Damage=damage, Life=2.4f, Radius=9, Pierce=rank==5?1:0 });
                    }
                    ArcaneCasts++;
                }
                else if (w == 4)
                {
                    Events.Add(new("aura", Position, range));
                    bool marks = IsFitted(WeaponCombo.Riptide);
                    foreach (var enemy in Enemies)
                    {
                        if (enemy.Health <= 0 || enemy.Emerging ||
                            Vector2.DistanceSquared(enemy.Position, Position) > (range + enemy.Radius) * (range + enemy.Radius)) continue;
                        if (marks) enemy.Drenched = 1.35f;
                        Hit(enemy, damage);
                    }
                }
                else if (w == 3)
                {
                    Vector2 from = Position; var chain = new HashSet<int>(); Enemy? hit = target;
                    for (int i = 0; i < 2 + rank && hit != null; i++)
                    {
                        chain.Add(hit.Id); Events.Add(new("arc", from, 0, hit.Position)); Hit(hit, damage);
                        from = hit.Position;
                        hit = Enemies.Where(e => e.Health > 0 && !e.Emerging && !chain.Contains(e.Id) && Vector2.DistanceSquared(e.Position,from) < MathF.Pow(180*Area,2)).OrderBy(e => Vector2.DistanceSquared(e.Position,from)).FirstOrDefault(e => World.OpenShot(from, e.Position));
                    }
                }
                else FireDeckWeapon(kind, target, origin, rank, damage);
            }
            Cooldowns[w] = (w==0?.85f:w==1?1.3f:w==2?(rank==5?1.65f:2.4f):w==4?.6f:w==5?1.19f:1.55f)
                / (1+ReloadRank*.12f);
        }
    }
    static float SegmentDistance(Vector2 p,Vector2 a,Vector2 b)
    {
        var v=b-a; float t=v.LengthSquared()>0?Math.Clamp(Vector2.Dot(p-a,v)/v.LengthSquared(),0,1):0;
        return Vector2.Distance(p,a+t*v);
    }
    void UpdateShots(float dt)
    {
        foreach (var s in Shots)
        {
            if (s.Life<=0) continue;
            if (s.Kind == WeaponKind.Arcane && !s.Hostile)
            {
                var target = Enemies.Where(e=>e.Health>0 && !e.Emerging && !s.Hit.Contains(e.Id) && Vector2.DistanceSquared(e.Position,s.Position)<650*650).OrderByDescending(e => !s.ComboSpent && e.Drenched > 0).ThenBy(e=>Vector2.DistanceSquared(e.Position,s.Position)).FirstOrDefault(e => World.OpenShot(s.Position, e.Position));
                if (target != null) s.Velocity = OceanWorld.Unit(Vector2.Lerp(s.Velocity/400,OceanWorld.Unit(target.Position-s.Position),1-MathF.Exp(-dt*7)))*400;
            }
            s.Previous=s.Position; s.Position+=s.Velocity*dt; s.Life-=dt; s.Age+=dt;
            if (s.Hostile)
            {
                // Boss bombs pass over boats and terrain, then burst at their fixed landing point.
                if (s.Life <= 0)
                {
                    s.Position = s.Target;
                    BossExplosions++;
                    Events.Add(new("bossExplosion", s.Target, s.Radius));
                    if (Vector2.Distance(Position, s.Target) < s.Radius + 23)
                    {
                        float before = Health;
                        DamagePlayer(s.Damage);
                        if (Health < before) BossBlastHits++;
                    }
                }
                continue;
            }
            if (s.Life<=0) continue;
            if (s.Kind==WeaponKind.Mine)
            {
                if (s.Life>0 && s.Age>=.5f && Enemies.Any(e=>e.Health>0 && Vector2.Distance(e.Position,s.Position)<55+e.Radius))
                {
                    s.Life=0; MinesExploded++; Events.Add(new("explosion",s.Position,s.Radius));
                    foreach(var e in Enemies) if(e.Health>0 && Vector2.Distance(e.Position,s.Position)<s.Radius+e.Radius) Hit(e,s.Damage);
                }
                continue;
            }
            var obstacle=World.Places.FirstOrDefault(p=>OceanWorld.IsSolid(p) && OceanWorld.Overlap(p,s.Position,2,out _,out _));
            if(obstacle!=null)
            {
                if(s.Kind==WeaponKind.Cannon && s.Bounces>0)
                {
                    OceanWorld.Overlap(obstacle,s.Position,2,out var normal,out _);
                    s.Velocity=Vector2.Reflect(s.Velocity,normal); s.Position=s.Previous+normal*3; s.Bounces--; s.Ricocheted = true;
                    CannonRicochets++; Events.Add(new("ricochet",s.Position));
                }
                else s.Life=0;
                continue;
            }
            foreach(var e in Enemies)
            {
                if(e.Health<=0 || e.Emerging || s.Hit.Contains(e.Id) || SegmentDistance(e.Position,s.Previous,s.Position)>e.Radius+s.Radius) continue;
                s.Hit.Add(e.Id);
                StrikeWithShot(s, e);
                if (BossSlain) break;
                if(s.Kind==WeaponKind.Cannon && s.Bounces>0)
                {
                    var next=Enemies.Where(other=>other.Health>0 && !other.Emerging && !s.Hit.Contains(other.Id) && Vector2.DistanceSquared(other.Position,e.Position)<320*320).OrderBy(other=>Vector2.DistanceSquared(other.Position,e.Position)).FirstOrDefault(other => World.OpenShot(e.Position, other.Position));
                    // An isolated hit ends here; reversing looks like the monster firing back.
                    if(next==null) { s.Life=0; break; }
                    s.Position=e.Position;
                    s.Velocity=OceanWorld.Unit(next.Position-e.Position)*650;
                    s.Bounces--; s.Ricocheted = true; CannonRicochets++; Events.Add(new("ricochet",s.Position)); break;
                }
                if(s.Pierce--<=0) { s.Life=0; break; }
            }
        }
    }
}
