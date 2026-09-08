using System.Numerics;
namespace BoatsNBeasts.Core;

public enum VoyageMode { Sailing, Fishing, Catch, Harbor, Upgrade, Paused, Defeat, Victory }
public enum BoatKind { Cutter, Trawler }
public enum EnemyKind { Crab, Puffer, Serpent, Ray, Leviathan }
public enum WeaponKind { Cannon, Harpoon, Mortar, Coil, Undertow, Broadside }
public sealed class Enemy
{
    public int Id; public EnemyKind Kind; public Vector2 Position, Direction;
    public float Health, MaxHealth, Time, AttackClock, Telegraph, Dash, Mark, HitFlash;
    public float Radius => Kind == EnemyKind.Leviathan ? 74 : Kind == EnemyKind.Serpent ? 31 : 27;
}
public sealed class Shot
{
    public Vector2 Position, Previous, Velocity, Target;
    public float Damage, Life, Radius; public bool Hostile;
    public WeaponKind Kind; public int Pierce;
    public HashSet<int> Hit = new();
}
public readonly record struct GameEvent(string Kind, Vector2 Position, float Value = 0, Vector2 End = default);
public sealed record CatchItem(string Name, int Value, bool Chart);
public readonly record struct SailInput(Vector2 Move, bool Boost);
public sealed class Voyage
{
    public OceanWorld World { get; }
    public SeedRandom Random;
    SeedRandom buildRandom, fishRandom;
    public SpawnDirector Director { get; } = new();
    public VoyageMode Mode = VoyageMode.Sailing;
    public BoatKind Boat;
    public Vector2 Position, Velocity;
    public float Heading, Health, Boost = 100, CombatTime, Invulnerable, Distance, MaxDistance;
    public int Coins = 20, Kills, Level = 1, Xp, Charts, HullRank, EngineRank, ReloadRank, AreaRank;
    public float AbilityCharge, Slipstream;
    public readonly List<int> UpgradeChoices = new();
    public bool BossSpawned, BossSlain, Retired, AssistedFishing;
    public bool BoostExhausted { get; private set; }
    public const float BroadsideHalfAngle = 1.2f;
    public readonly int[] Weapons = new int[6];
    public readonly float[] Cooldowns = new float[6];
    public readonly List<Enemy> Enemies = new();
    public readonly List<Shot> Shots = new();
    public readonly List<CatchItem> Hold = new();
    public readonly List<GameEvent> Events = new();
    public readonly HashSet<string> ChartSchools = new();
    public int NextEnemyId;
    public Place? FishingPlace;
    public float FishingTime, FishCursor, FishTarget, FishResultTime, ReelCooldown;
    public int FishHits, FishMisses;
    public string CatchTitle = "", CatchDetail = "";
    public BoatSpec Spec => BoatSpec.For(Boat);
    public float MaxHealth => Spec.Hull + HullRank * 25;
    public float Speed => Spec.Speed * (1 + EngineRank * .1f);
    public int Tier => OceanWorld.TierAt(Position);
    public int NextXp => 7 + Level * 5;
    public bool Safe => World.HarborAt(Position) != null;
    public float FishBand => .14f;
    public float Area => 1 + AreaRank * .15f;
    public Voyage(uint seed, BoatKind boat)
    {
        World = new(seed); Random = new(seed ^ 0xa129f); buildRandom = new(seed ^ 0x77291); fishRandom = new(seed ^ 0x99a12); Boat = boat; Health = MaxHealth;
        Weapons[0] = 1; Weapons[boat == BoatKind.Cutter ? 5 : 4] = 1;
        World.Stream(Position);
    }
    public void Tick(float dt, SailInput input)
    {
        dt = Math.Clamp(dt, 0, .05f);
        if (Mode == VoyageMode.Fishing)
        {
            FishingTime += dt; ReelCooldown = Math.Max(0, ReelCooldown - dt);
            FishCursor = .5f + .46f * MathF.Sin(FishingTime * (2.7f + Tier * .07f));
            if (AssistedFishing && ReelCooldown <= 0 && FishingTime > .6f && Math.Abs(FishCursor-FishTarget) < FishBand * .75f) Reel();
            if (Mode == VoyageMode.Fishing && FishingTime >= 16) FinishFishing(false);
            return;
        }
        if (Mode != VoyageMode.Sailing) return;
        CombatTime += dt; Invulnerable = Math.Max(0, Invulnerable - dt);
        Vector2 direction = OceanWorld.Unit(input.Move);
        if (!input.Boost) BoostExhausted = false;
        bool boosting = input.Boost && !BoostExhausted && Boost > 0 && direction != Vector2.Zero;
        Boost = Math.Clamp(Boost + dt * (boosting ? -38 : input.Boost && BoostExhausted ? 0 : 23), 0, 100);
        if (boosting && Boost <= 0) BoostExhausted = true;
        Vector2 wanted = direction * Speed * (boosting ? 1.85f : 1);
        Velocity = Vector2.Lerp(Velocity, wanted, 1 - MathF.Exp(-dt * (direction == Vector2.Zero ? 5 : 7)));
        if (Velocity.LengthSquared() > 20) Heading = ApproachAngle(Heading, MathF.Atan2(Velocity.Y, Velocity.X) + MathF.PI / 2, dt * 9);
        var old = Position;
        float hullRadius = Boat == BoatKind.Cutter ? 30 : 37;
        Position = World.Slide(old, Position + Velocity * dt, hullRadius);
        // A two-disc capsule follows the long hull; the prow cannot cut into an island.
        var bow = new Vector2(MathF.Sin(Heading), -MathF.Cos(Heading)) * 35;
        for (int pass = 0; pass < 2; pass++)
        {
            Position += World.Slide(old + bow, Position + bow, hullRadius) - (Position + bow);
            Position += World.Slide(old - bow, Position - bow, hullRadius) - (Position - bow);
        }
        Distance += Vector2.Distance(old, Position); MaxDistance = Math.Max(MaxDistance, Position.Length());
        World.Stream(Position);
        foreach (var p in World.Places) if (Vector2.Distance(Position, p.Position) < 680) World.Discovered.Add(p.Id);
        if (boosting && ((int)(CombatTime * 25) != (int)((CombatTime - dt) * 25))) Events.Add(new("boost", Position));
        bool safe = Safe;
        int spawn = BossSlain && !Retired ? 0 : Director.Tick(dt, Tier, Enemies.Count(e => e.Kind != EnemyKind.Leviathan), safe, BossSpawned && !BossSlain);
        for (int i = 0; i < spawn; i++) Spawn();
        if (Charts >= 3 && Tier >= 3 && !BossSpawned && !safe)
        {
            if (Spawn(EnemyKind.Leviathan))
            {
                BossSpawned = true;
                foreach (var escort in Enemies.Where(e => e.Kind != EnemyKind.Leviathan && e.Health > 0).OrderBy(e => Vector2.DistanceSquared(e.Position, Position)).Skip(8)) escort.Health = 0;
                Events.Add(new("boss", Enemies[^1].Position));
            }
        }
        UpdateAbility(dt, safe, boosting);
        UpdateEnemies(dt, safe, boosting);
        UpdateWeapons(dt, safe);
        UpdateShots(dt, safe, boosting);
        Enemies.RemoveAll(e => e.Health <= 0 || (e.Kind != EnemyKind.Leviathan && Vector2.DistanceSquared(e.Position, Position) > 1600 * 1600));
        Shots.RemoveAll(s => s.Life <= 0);
        if (Health <= 0) { Health = 0; Mode = VoyageMode.Defeat; Events.Add(new("defeat", Position)); }
        else if (Xp >= NextXp) { Xp -= NextXp; Level++; RollUpgrades(); Mode = VoyageMode.Upgrade; Events.Add(new("level", Position)); }
    }
    static float ApproachAngle(float from, float to, float amount) => from + MathF.Atan2(MathF.Sin(to - from), MathF.Cos(to - from)) * Math.Min(1, amount);
    public bool Spawn(EnemyKind? forced = null)
    {
        if (Enemies.Count >= 80) return false;
        var kind = forced ?? (Tier == 0 ? EnemyKind.Crab : (EnemyKind)Random.Index(Math.Min(4, Tier + 1)));
        Vector2 p = default;
        for (int attempt = 0; attempt < 20; attempt++)
        {
            float angle = Random.Range(0, MathF.Tau);
            p = Position + new Vector2(MathF.Cos(angle), MathF.Sin(angle)) * Random.Range(760, 940);
            if (World.IsWater(p, 80) && World.HarborAt(p) == null) break;
            if (attempt == 19) return false;
        }
        float hp = (kind == EnemyKind.Leviathan ? 1050 : kind == EnemyKind.Crab ? 27 : kind == EnemyKind.Puffer ? 38 : kind == EnemyKind.Ray ? 43 : 52) * (1 + Tier * .25f);
        Enemies.Add(new() { Id = ++NextEnemyId, Kind = kind, Position = p, Health = hp, MaxHealth = hp, AttackClock = Random.Range(1, 3) });
        return true;
    }
    void UpdateEnemies(float dt, bool safe, bool boosting)
    {
        // Population is capped at 80; small pairwise local separation keeps silhouettes legible.
        foreach (var e in Enemies)
        {
            if (e.Health <= 0) continue;
            e.Time += dt; e.AttackClock -= dt; e.Mark = Math.Max(0, e.Mark - dt); e.HitFlash = Math.Max(0, e.HitFlash - dt);
            Vector2 d = Position - e.Position; float distance = d.Length(); Vector2 dir = OceanWorld.Unit(d, Vector2.UnitY);
            float speed = (e.Kind == EnemyKind.Crab ? 83 : e.Kind == EnemyKind.Puffer ? 69 : e.Kind == EnemyKind.Serpent ? 111 : e.Kind == EnemyKind.Ray ? 135 : 73) * (1 + Math.Min(Tier, 12) * .045f);
            if (e.Mark > 0) speed *= .62f;
            Vector2 motion = dir;
            if (e.Kind == EnemyKind.Puffer)
            {
                motion = distance < 310 ? -dir * .6f : distance < 390 ? new(-dir.Y * .3f, dir.X * .3f) : dir;
                if (e.AttackClock <= .65f && e.AttackClock > 0) e.Telegraph = .65f;
                if (e.AttackClock <= 0 && !safe) { FireHostile(e, dir, 200); e.AttackClock = 3.8f; e.Telegraph = 0; }
            }
            if (e.Kind == EnemyKind.Serpent)
            {
                if (e.AttackClock <= 0 && e.Dash <= 0) { e.Telegraph = .85f; e.Direction = dir; e.AttackClock = 4.3f; }
                if (e.Telegraph > 0) { e.Telegraph -= dt; motion *= .1f; if (e.Telegraph <= 0) e.Dash = .7f; }
                if (e.Dash > 0) { e.Dash -= dt; motion = e.Direction; speed *= 3.4f; }
            }
            if (e.Kind == EnemyKind.Ray)
            {
                // Circle the captain, then send a telegraphed fan across their course.
                motion = dir * (distance > 370 ? 1 : distance < 260 ? -.6f : .1f) + new Vector2(-dir.Y, dir.X) * (e.Id % 2 == 0 ? .8f : -.8f);
                e.Telegraph = e.AttackClock < .7f ? Math.Max(0, e.AttackClock) : 0;
                if (e.AttackClock <= 0 && !safe)
                {
                    for (int i = -1; i <= 1; i++) { float a = MathF.Atan2(dir.Y, dir.X) + i * .24f; FireHostile(e, new(MathF.Cos(a), MathF.Sin(a)), 230); }
                    e.AttackClock = 4.8f;
                }
            }
            if (e.Kind == EnemyKind.Leviathan)
            {
                if (distance > 1200) e.Position = Position - dir * 1000;
                if (e.AttackClock < 1) e.Telegraph = Math.Max(0, e.AttackClock);
                if (e.AttackClock <= 0 && !safe)
                {
                    int n = e.Health < e.MaxHealth * .5f ? 16 : 12;
                    for (int i = 0; i < n; i++) { float a = MathF.Tau * i / n + e.Time * .3f; FireHostile(e, new(MathF.Cos(a), MathF.Sin(a)), 155); }
                    e.AttackClock = e.Health < e.MaxHealth * .5f ? 2.8f : 3.7f;
                    Events.Add(new("slam", e.Position));
                }
                if (distance < 220) motion *= .2f;
            }
            foreach (var other in Enemies)
            {
                if (other == e || other.Health <= 0) continue;
                var sep = e.Position - other.Position; float len = sep.Length();
                if (len > .1f && len < e.Radius + other.Radius) motion += sep / len * .65f;
            }
            var harbor = World.Places.FirstOrDefault(p => p.Kind == PlaceKind.Harbor && Vector2.Distance(p.Position, e.Position) < 315);
            if (harbor != null) motion = OceanWorld.Unit(e.Position - harbor.Position);
            motion = World.Avoid(e.Position, motion, e.Radius, e.Id);
            e.Position = World.Slide(e.Position, e.Position + motion * speed * dt, e.Radius);
            if (!safe && distance < e.Radius + 23) DamagePlayer(e.Kind == EnemyKind.Leviathan ? 24 : 11 + Tier * 1.5f, boosting);
        }
    }
    void FireHostile(Enemy e, Vector2 dir, float speed)
    {
        if (Shots.Count > 360) return;
        Shots.Add(new() { Hostile = true, Position = e.Position, Previous = e.Position, Velocity = dir * speed, Damage = 10 + Tier * 1.4f, Life = 6, Radius = 7 });
    }
    void DamagePlayer(float damage, bool boosting)
    {
        if (Invulnerable > 0 || Safe || Mode != VoyageMode.Sailing) return;
        Health -= damage * (boosting ? .45f : Boat == BoatKind.Trawler && Velocity.Length() < Speed * .45f ? .7f : 1); Invulnerable = .8f; Events.Add(new("hurt", Position, damage));
    }
    void UpdateWeapons(float dt, bool safe)
    {
        for (int w = 0; w < Weapons.Length; w++)
        {
            Cooldowns[w] = Math.Max(0, Cooldowns[w] - dt);
            if (Weapons[w] == 0 || Cooldowns[w] > 0 || safe) continue;
            float range = w == 4 ? (130 + Weapons[w] * 8) * Area : w == 5 ? 195 * Area : w == 3 ? 285 * Area : w == 2 ? 610 : 570;
            Enemy? target = null; float near = range * range;
            foreach (var e in Enemies) { float d = Vector2.DistanceSquared(e.Position, Position); if (e.Health > 0 && d < near) { near = d; target = e; } }
            if (target == null) continue;
            int rank = Weapons[w]; float damage = (w == 0 ? 15 : w == 1 ? 13 : w == 2 ? 35 : w == 4 ? 7 : w == 5 ? 28 : 18) * (1 + .40f * (rank - 1));
            Cooldowns[w] = (w == 0 ? .65f : w == 1 ? 1.2f : w == 2 ? 2.4f : w == 4 ? .6f : w == 5 ? 1.7f : 1.55f) / ((1 + .1f * (rank - 1)) * (1 + ReloadRank * .12f) * (Slipstream > 0 ? 1.65f : 1));
            if (w is 4 or 5)
            {
                Vector2 aim = OceanWorld.Unit(target.Position - Position);
                Events.Add(new(w == 4 ? "aura" : "broadside", Position, range, Position + aim * range));
                foreach (var e in Enemies)
                {
                    var offset = e.Position - Position;
                    if (e.Health <= 0 || offset.Length() > range + e.Radius) continue;
                    if (w == 5 && Vector2.Dot(OceanWorld.Unit(offset), aim) < MathF.Cos(BroadsideHalfAngle)) continue;
                    Hit(e, damage * (w == 5 && e.Mark > 0 ? 1.35f : 1));
                    if (w == 5) e.Position = World.Slide(e.Position, e.Position + OceanWorld.Unit(offset) * (28 + rank * 5), e.Radius);
                }
            }
            else if (w == 3)
            {
                Vector2 from = Position; var chain = new HashSet<int>(); Enemy? hit = target;
                for (int i = 0; i < 2 + rank && hit != null; i++)
                {
                    chain.Add(hit.Id); Events.Add(new("arc", from, 0, hit.Position)); Hit(hit, damage * (hit.Mark > 0 ? 1.8f : 1));
                    from = hit.Position; hit = Enemies.Where(e => e.Health > 0 && !chain.Contains(e.Id) && Vector2.DistanceSquared(e.Position, from) < MathF.Pow(180 * Area, 2)).OrderBy(e => Vector2.DistanceSquared(e.Position, from)).FirstOrDefault();
                }
            }
            else
            {
                Vector2 dir = OceanWorld.Unit(target.Position - Position);
                int count = w == 0 && rank >= 3 ? 2 : 1;
                for (int i = 0; i < count; i++)
                {
                    float hullScale = Boat == BoatKind.Cutter ? 139f / 145 : 151f / 145;
                    Vector2 bowMount = new Vector2(MathF.Sin(Heading), -MathF.Cos(Heading)) * (48 * hullScale);
                    if (w == 0) dir = OceanWorld.Unit(target.Position - (Position + bowMount));
                    Vector2 start = Position + (w == 0 ? bowMount + dir * (24 * hullScale) : dir * 29) + new Vector2(-dir.Y, dir.X) * (count == 2 ? (i == 0 ? -9 : 9) : 0);
                    Shots.Add(new() { Kind = (WeaponKind)w, Position = start, Previous = start, Velocity = dir * (w == 1 ? 580 : w == 2 ? 370 : 650), Target = target.Position, Damage = damage, Life = w == 2 ? Vector2.Distance(start, target.Position) / 370 : 1.05f, Radius = w == 2 ? (95 + rank * 9) * Area : 6, Pierce = w == 1 ? rank : 0 });
                }
            }
            if (w < 3) Events.Add(new(w == 0 ? "shot" : w == 1 ? "harpoon" : "mortar", Position));
        }
    }
    static float SegmentDistance(Vector2 p, Vector2 a, Vector2 b)
    {
        Vector2 v = b - a; float t = v.LengthSquared() > 0 ? Math.Clamp(Vector2.Dot(p - a, v) / v.LengthSquared(), 0, 1) : 0;
        return Vector2.Distance(p, a + t * v);
    }
    void UpdateShots(float dt, bool safe, bool boosting)
    {
        foreach (var s in Shots)
        {
            if (s.Life <= 0) continue;
            s.Previous = s.Position; s.Position += s.Velocity * dt; s.Life -= dt;
            if (s.Hostile)
            {
                if (World.HarborAt(s.Position) != null) { s.Life = 0; continue; }
                if (SegmentDistance(Position, s.Previous, s.Position) < 26 + s.Radius) { if (!safe) DamagePlayer(s.Damage, boosting); s.Life = 0; }
                if (!World.IsWater(s.Position, 1)) s.Life = 0;
                continue;
            }
            if (s.Kind == WeaponKind.Mortar)
            {
                if (s.Life <= 0)
                {
                    Events.Add(new("explosion", s.Position, s.Radius));
                    foreach (var e in Enemies) if (e.Health > 0 && Vector2.Distance(e.Position, s.Position) < s.Radius + e.Radius) Hit(e, s.Damage * (e.Mark > 0 ? 1.5f : 1));
                }
                continue;
            }
            foreach (var e in Enemies)
            {
                if (e.Health <= 0 || s.Hit.Contains(e.Id) || SegmentDistance(e.Position, s.Previous, s.Position) > e.Radius + s.Radius) continue;
                s.Hit.Add(e.Id); Hit(e, s.Damage);
                if (s.Kind == WeaponKind.Harpoon) e.Mark = 4.5f + Weapons[1] * .3f;
                if (s.Pierce-- <= 0) { s.Life = 0; break; }
            }
            if (!World.IsWater(s.Position, 2)) s.Life = 0;
        }
    }
    void Hit(Enemy e, float damage)
    {
        e.Health -= damage; e.HitFlash = .12f; Events.Add(new("hit", e.Position, damage));
        if (e.Health > 0) return;
        Kills++; Xp += e.Kind == EnemyKind.Leviathan ? 25 : 1; Coins += 1 + Tier / 2;
        Events.Add(new("kill", e.Position, e.Kind == EnemyKind.Leviathan ? 2 : 1));
        if (e.Kind == EnemyKind.Leviathan)
        {
            BossSlain = true; Coins += 150;
            // The defeated sovereign disperses its escort. The journey home is the reward.
            // Mark dead/expired rather than mutate lists being traversed by the current attack.
            foreach (var other in Enemies) other.Health = 0;
            foreach (var shot in Shots) shot.Life = 0;
            Events.Add(new("bossSlain", Position)); Events.Add(new("calm", Position, 1000));
        }
    }
    public bool Interact()
    {
        if (Mode != VoyageMode.Sailing) return false;
        if (World.HarborAt(Position) != null) { Mode = VoyageMode.Harbor; Velocity = Vector2.Zero; return true; }
        var fish = World.FishAt(Position);
        if (fish == null || Hold.Count >= 12) return false;
        FishingPlace = fish; Mode = VoyageMode.Fishing; FishingTime = ReelCooldown = 0; FishHits = FishMisses = 0;
        fishRandom = new(SeedRandom.Hash(World.Seed, OceanWorld.KeyAt(fish.Position).X, OceanWorld.KeyAt(fish.Position).Y, fish.Style ^ (uint)World.Depletion.GetValueOrDefault(fish.Id)));
        FishCursor = .5f; FishTarget = fishRandom.Range(.25f, .75f); Events.Add(new("cast", fish.Position)); return true;
    }
    public void Reel()
    {
        if (Mode != VoyageMode.Fishing || FishingTime < .25f || ReelCooldown > 0) return;
        ReelCooldown = .65f;
        if (Math.Abs(FishCursor - FishTarget) < FishBand) { FishHits++; Events.Add(new("reel", Position)); FishTarget = fishRandom.Range(.22f, .78f); }
        else { FishMisses++; Events.Add(new("miss", Position)); }
        if (FishHits >= 3) FinishFishing(true);
        else if (FishMisses >= 3) FinishFishing(false);
    }
    void FinishFishing(bool success)
    {
        if (FishingPlace == null) return;
        World.Depletion[FishingPlace.Id] = World.Depletion.GetValueOrDefault(FishingPlace.Id) + 1;
        if (success)
        {
            string[] names = ["Silver sprat", "Coral snapper", "Moonfin tuna", "Golden lanternfish", "Abyssal stargazer"];
            int rarity = Math.Min(4, Tier + (fishRandom.Unit() > .7f ? 1 : 0));
            bool chart = Tier >= 1 && Charts < 3 && ChartSchools.Add(FishingPlace.Id);
            if (chart) Charts++;
            var item = new CatchItem(names[rarity], 14 + rarity * 13 + Tier * 4, chart); Hold.Add(item);
            CatchTitle = item.Name; CatchDetail = $"Worth {item.Value} gold at harbor" + (chart ? $"  •  Chart fragment {Charts}/3 recovered!" : "");
            Events.Add(new("catch", Position));
        }
        else { CatchTitle = "The one that got away"; CatchDetail = "Three clean reels land a catch. Another school awaits."; Events.Add(new("miss", Position)); }
        Mode = VoyageMode.Catch;
    }
    public void CancelFishing() { if (Mode == VoyageMode.Fishing) { FishingPlace = null; Mode = VoyageMode.Sailing; } }
    public int Sell()
    {
        if (Mode != VoyageMode.Harbor) return 0;
        int value = Hold.Sum(f => f.Value); Coins += value; Hold.Clear(); if (value > 0) Events.Add(new("buy", Position)); return value;
    }
    public int RepairCost => (int)MathF.Ceiling((MaxHealth - Health) / 3);
    public bool Repair()
    {
        if (Mode != VoyageMode.Harbor || RepairCost <= 0 || Coins < RepairCost) return false;
        Coins -= RepairCost; Health = MaxHealth; Events.Add(new("buy", Position)); return true;
    }
    void UpdateAbility(float dt, bool safe, bool boosting)
    {
        Slipstream = Math.Max(0, Slipstream - dt);
        if (Boat == BoatKind.Cutter) { if (boosting) Slipstream = 1.25f; AbilityCharge = 0; return; }
        Slipstream = 0;
        if (safe) return;
        AbilityCharge = Math.Min(1, AbilityCharge + dt * (Velocity.Length() < Speed * .45f ? .34f : .08f));
        if (AbilityCharge < 1 || !Enemies.Any(e => e.Health > 0 && Vector2.Distance(e.Position, Position) < 310)) return;
        AbilityCharge = 0;
        Events.Add(new("bulwark", Position, 270));
        foreach (var shot in Shots) if (shot.Hostile && Vector2.Distance(shot.Position, Position) < 270) shot.Life = 0;
        foreach (var e in Enemies)
            if (e.Health > 0 && Vector2.Distance(e.Position, Position) < 270 + e.Radius)
            { e.Mark = 3; Hit(e, 18 + Level * 2); e.Position = World.Slide(e.Position, e.Position + OceanWorld.Unit(e.Position - Position) * 65, e.Radius); }
    }
    void RollUpgrades()
    {
        UpgradeChoices.Clear();
        var available = Enumerable.Range(0, UpgradeNames.Length).Where(i => Rank(i) < 5).ToList();
        // A weapon is always offered while one can still improve; remaining choices vary by seed/run.
        var weapons = available.Where(i => i < Weapons.Length).ToArray();
        if (weapons.Length > 0) { int first = weapons[buildRandom.Index(weapons.Length)]; UpgradeChoices.Add(first); available.Remove(first); }
        while (UpgradeChoices.Count < 3 && available.Count > 0) { int i = buildRandom.Index(available.Count); UpgradeChoices.Add(available[i]); available.RemoveAt(i); }
    }
    public int Rank(int option) => option < 6 ? Weapons[option] : option == 6 ? HullRank : option == 7 ? EngineRank : option == 8 ? ReloadRank : AreaRank;
    public int UpgradeCost(int option) => 26 + Rank(option) * 22;
    public bool Upgrade(int option, bool free = false)
    {
        if (option < 0 || option >= UpgradeNames.Length || Rank(option) >= 5 || (free ? Mode != VoyageMode.Upgrade || !UpgradeChoices.Contains(option) : Mode != VoyageMode.Harbor)) return false;
        if (!free && Coins < UpgradeCost(option)) return false;
        if (!free) Coins -= UpgradeCost(option);
        if (option < 6) Weapons[option]++;
        else if (option == 6) { HullRank++; Health += 25; }
        else if (option == 7) EngineRank++;
        else if (option == 8) ReloadRank++;
        else AreaRank++;
        if (free) Mode = VoyageMode.Sailing;
        Events.Add(new("buy", Position)); return true;
    }
    public bool SwitchBoat()
    {
        if (Mode != VoyageMode.Harbor) return false;
        float ratio = Health / MaxHealth; Boat = Boat == BoatKind.Cutter ? BoatKind.Trawler : BoatKind.Cutter; Health = MaxHealth * ratio; AbilityCharge = Slipstream = 0;
        Events.Add(new("buy", Position)); return true;
    }
    public void ClaimVictory() { if (Mode == VoyageMode.Harbor && BossSlain) { Retired = true; Mode = VoyageMode.Victory; Events.Add(new("victory", Position)); } }
    public static readonly string[] UpgradeNames = ["Deck cannon", "Barbed harpoon", "Depth mortar", "Storm coil", "Undertow aura", "Scatter broadside", "Reinforced hull", "Tuned engine", "Quick loader", "Wide powder"];
    public static readonly string[] UpgradeDescriptions = [
        "RANGED · Fast shots. More damage and faster fire each rank. Rank 3 adds a second barrel.",
        "RANGED · Pierces and slows. Soaked foes take bonus blast, coil and broadside damage.",
        "RANGED · Lobbed area blasts. Each rank adds damage, blast size and fire rate. +50% vs soaked.",
        "CHAIN · Lightning jumps through a pack. Each rank adds a jump. +80% vs soaked.",
        "AURA · A constant damaging current surrounds you. Each rank adds damage, reach and pulse speed.",
        "CLOSE · A wide automatic scatter blast. Pushes packs back. Each rank hits harder and faster.",
        "+25 maximum hull. Repairs the new plating immediately.",
        "+10% sailing speed. Dodge, explore, and control your distance.",
        "+12% fire rate for every weapon, aura and close-range attack.",
        "+15% area for aura, broadside, blasts and chain reach."];
}

public sealed record BoatSpec(string Name, float Hull, float Speed, string Ability, string Description)
{
    public static readonly BoatSpec[] All = [
        new("Cutter", 100, 235, "SLIPSTREAM", "Boost grants +65% fire rate, lasting 1.25s after release. Cannon + close scatter blast."),
        new("Trawler", 155, 185, "BULWARK", "Moving slowly charges a pulse that clears shots and soaks foes. 30% less damage at low speed. Cannon + aura.")
    ];
    public static BoatSpec For(BoatKind kind) => All[(int)kind];
}
