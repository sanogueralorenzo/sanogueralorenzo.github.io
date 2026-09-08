using System.Numerics;
namespace BoatsNBeasts.Core;

public enum VoyageMode { Sailing, Fishing, Harbor, Upgrade, Paused, Defeat, Victory }
public enum BoatKind { Cutter, Trawler, Mage }
public enum EnemyKind { Crab, Puffer, Serpent, Ray, Leviathan }
public enum WeaponKind { Cannon, Harpoon, Mine, Coil, Undertow, Arcane }
public sealed class Enemy
{
    public int Id; public EnemyKind Kind; public Vector2 Position, Direction;
    public float Health, MaxHealth, Time, AttackClock, Telegraph, Dash, HitFlash, Pull, Fuse;
    public bool Swift;
    public float SpeedMultiplier => Swift ? 1.5f : 1;
    public const float PufferFuseDuration = 1.05f, PufferTriggerRadius = 125, PufferBlastRadius = 155;
    public const float EmergenceDuration = .45f;
    public bool Emerging => Time < EmergenceDuration;
    public float Radius => Kind == EnemyKind.Leviathan ? 74 : Kind == EnemyKind.Serpent ? 31 : 27;
}
public sealed class Shot
{
    public Vector2 Position, Previous, Velocity;
    public float Damage, Life, Radius, Age; public bool Hostile;
    public WeaponKind Kind; public int Pierce, Bounces;
    public HashSet<int> Hit = new();
}
public readonly record struct GameEvent(string Kind, Vector2 Position, float Value = 0, Vector2 End = default);
public sealed record CatchItem(string Name, int Value);
public readonly record struct SailInput(Vector2 Move, bool Boost);
public sealed partial class Voyage
{
    public OceanWorld World { get; }
    public SeedRandom Random;
    SeedRandom buildRandom, fishRandom;
    readonly System.Random silverRandom = new();
    public int SilverEarned { get; private set; }
    public float NextSilverTime { get; private set; }
    float SilverInterval() => 45 + silverRandom.NextSingle() * 45;
    public SpawnDirector Director { get; } = new();
    public VoyageMode Mode = VoyageMode.Sailing;
    public BoatKind Boat { get; }
    public Vector2 Position, Velocity;
    public float Heading, Health, Boost = 100, CombatTime, Invulnerable, Distance, MaxDistance;
    public int Coins = 20, Kills, Level = 1, Xp, HullRank, EngineRank, ReloadRank, AreaRank;
    public float AbilityCharge;
    public float FireRateMultiplier => Boat == BoatKind.Cutter && IsBoosting ? 1.65f : 1;
    public readonly List<int> UpgradeChoices = new();
    public bool BossSpawned, BossSlain;
    public bool BoostExhausted { get; private set; }
    public const int BaseWeaponSlots = 2, MaxWeaponSlots = 5;
    public int WeaponSlots { get; }
    public int WeaponCount => Weapons.Count(rank => rank > 0);
    public readonly int[] Weapons = new int[6];
    public readonly float[] Cooldowns = new float[6];
    public readonly List<Enemy> Enemies = new();
    public readonly List<Shot> Shots = new();
    public readonly List<CatchItem> Hold = new();
    public readonly List<GameEvent> Events = new();
    public int NextEnemyId;
    public int PufferExplosions, PufferBlastHits;
    public Place? FishingPlace;
    public float FishingTime, FishCursor, FishTarget;
    public string CatchTitle = "";
    public BoatSpec Spec => BoatSpec.For(Boat);
    public float MaxHealth => Spec.Hull + HullRank * 25;
    public float Speed => Spec.Speed * (1 + EngineRank * .1f);
    public int Tier => OceanWorld.TierAt(Position);
    public int PendingUpgrades { get; private set; }
    public float WhirlpoolRadius => (138 + Math.Max(0, Weapons[4] - 1) * 30) * Area;
    public int NextXp => 7 + Level * 5;
    public bool Safe => World.HarborAt(Position) != null;
    public float FishBand => .14f;
    public float Area => 1 + AreaRank * .15f;
    public Voyage(uint seed, BoatKind boat, int extraWeaponSlots = 0)
    {
        World = new(seed); Random = new(seed ^ 0xa129f); buildRandom = new(seed ^ 0x77291); fishRandom = new(seed ^ 0x99a12); Boat = boat; Health = MaxHealth;
        WeaponSlots = BaseWeaponSlots + Math.Clamp(extraWeaponSlots, 0, MaxWeaponSlots - BaseWeaponSlots);
        Weapons[boat == BoatKind.Cutter ? 0 : boat == BoatKind.Trawler ? 4 : 5] = 1;
        NextSilverTime = SilverInterval();
        Position = StartingArea.Spawn;
        Heading = MathF.PI;
        World.Stream(Position);
    }
    public void Tick(float dt, SailInput input)
    {
        dt = Math.Clamp(dt, 0, .05f);
        if (Mode == VoyageMode.Fishing)
        {
            FishingTime += dt;
            FishCursor = .5f + .46f * MathF.Sin(FishingTime * (2.7f + Tier * .07f));
            if (Mode == VoyageMode.Fishing && FishingTime >= 8) FinishFishing(false);
            return;
        }
        if (Mode != VoyageMode.Sailing) return;
        CombatTime += dt; Invulnerable = Math.Max(0, Invulnerable - dt);
        UpdateMovement(dt, input);
        CollectEncounters();
        bool safe = Safe;
        int spawn = Director.Tick(dt, Tier, Enemies.Count(e => e.Kind != EnemyKind.Leviathan), safe, BossSpawned && !BossSlain);
        for (int i = 0; i < spawn; i++) Spawn();
        if (Tier >= 3 && !BossSpawned && !safe)
        {
            if (Spawn(EnemyKind.Leviathan))
            {
                BossSpawned = true;
                foreach (var escort in Enemies.Where(e => e.Kind != EnemyKind.Leviathan && e.Health > 0).OrderBy(e => Vector2.DistanceSquared(e.Position, Position)).Skip(8)) escort.Health = 0;
                Events.Add(new("boss", Enemies[^1].Position));
            }
        }
        UpdateAbility(dt);
        UpdateEnemies(dt, safe);
        UpdateWeapons(dt, safe);
        UpdateShots(dt, safe);
        Enemies.RemoveAll(e => e.Health <= 0 || (e.Kind != EnemyKind.Leviathan && Vector2.DistanceSquared(e.Position, Position) > 1600 * 1600));
        Shots.RemoveAll(s => s.Life <= 0);
        if (Mode == VoyageMode.Victory) return;
        if (Health <= 0) { Health = 0; Mode = VoyageMode.Defeat; Events.Add(new("defeat", Position)); }
        else
        {
            while (Xp >= NextXp) { Xp -= NextXp; Level++; PendingUpgrades++; Events.Add(new("level", Position)); }
            if (PendingUpgrades > 0) PrepareNextUpgrade();
        }
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
        Enemies.Add(new() { Id = ++NextEnemyId, Kind = kind, Position = p, Health = hp, MaxHealth = hp, AttackClock = Random.Range(1, 3), Swift = kind != EnemyKind.Leviathan && Random.Index(4) == 0 });
        return true;
    }
    void UpdateEnemies(float dt, bool safe)
    {
        // Population is capped at 80; small pairwise local separation keeps silhouettes legible.
        foreach (var e in Enemies)
        {
            if (e.Health <= 0) continue;
            e.Time += dt;
            if (e.Emerging) continue;
            e.AttackClock -= dt; e.HitFlash = Math.Max(0, e.HitFlash - dt);
            Vector2 d = Position - e.Position; float distance = d.Length(); Vector2 dir = OceanWorld.Unit(d, Vector2.UnitY);
            float speed = (e.Kind == EnemyKind.Crab ? 83 : e.Kind == EnemyKind.Puffer ? 105 : e.Kind == EnemyKind.Serpent ? 111 : e.Kind == EnemyKind.Ray ? 135 : 73) * (1 + Math.Min(Tier, 12) * .045f) * e.SpeedMultiplier;
            Vector2 motion = dir;
            if (e.Kind == EnemyKind.Puffer)
            {
                // Once armed, hold still and commit to the blast; sailing away avoids it.
                if (safe) e.Fuse = 0;
                else if (e.Fuse > 0)
                {
                    e.Fuse = Math.Max(0, e.Fuse - dt);
                    if (e.Fuse <= 0)
                    {
                        e.Health = 0;
                        PufferExplosions++;
                        Events.Add(new("pufferExplosion", e.Position, Enemy.PufferBlastRadius));
                        if (distance < Enemy.PufferBlastRadius + 23)
                        {
                            float before = Health;
                            DamagePlayer(22 + Tier * 2);
                            if (Health < before) PufferBlastHits++;
                        }
                    }
                    continue;
                }
                else if (distance <= Enemy.PufferTriggerRadius)
                {
                    e.Fuse = Enemy.PufferFuseDuration;
                    continue;
                }
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
            if (e.Pull > 0)
            {
                e.Pull = Math.Max(0, e.Pull - dt);
                if (distance > 110) motion += dir * ((320 + (Weapons[1] - 1) * 160) / speed) * (e.Kind == EnemyKind.Leviathan ? .25f : 1);
            }
            motion = World.Avoid(e.Position, motion, e.Radius, e.Id);
            e.Position = World.Slide(e.Position, e.Position + motion * speed * dt, e.Radius);
            if (!safe && e.Kind != EnemyKind.Puffer && distance < e.Radius + 23) DamagePlayer(e.Kind == EnemyKind.Leviathan ? 24 : 11 + Tier * 1.5f);
        }
    }
    void FireHostile(Enemy e, Vector2 dir, float speed)
    {
        if (Shots.Count > 360) return;
        Shots.Add(new() { Hostile = true, Position = e.Position, Previous = e.Position, Velocity = dir * speed, Damage = 10 + Tier * 1.4f, Life = 6, Radius = 7 });
    }
    void DamagePlayer(float damage)
    {
        if (Invulnerable > 0 || Safe || Mode != VoyageMode.Sailing) return;
        Health -= damage; Invulnerable = .8f; Events.Add(new("hurt", Position, damage));
    }
    void Hit(Enemy e, float damage)
    {
        e.Health -= damage; e.HitFlash = .12f; Events.Add(new("hit", e.Position, damage));
        if (e.Health > 0) return;
        Kills++; Xp += e.Kind == EnemyKind.Leviathan ? 25 : 1; Coins += 1 + Tier / 2;
        // Megabonk-inspired time gate, with our own randomized interval.
        // Schedule from this award: idle time cannot bank a burst of drops.
        if (CombatTime >= NextSilverTime)
        {
            SilverEarned++;
            NextSilverTime = CombatTime + SilverInterval();
            Events.Add(new("silver", e.Position));
        }
        Events.Add(new("kill", e.Position, e.Kind == EnemyKind.Leviathan ? 2 : 1));
        if (e.Kind == EnemyKind.Leviathan)
        {
            BossSlain = true; Coins += 150; Mode = VoyageMode.Victory;
            // The defeated sovereign disperses its escort and ends the voyage.
            // Mark dead/expired rather than mutate lists being traversed by the current attack.
            foreach (var other in Enemies) other.Health = 0;
            foreach (var shot in Shots) shot.Life = 0;
            Events.Add(new("victory", Position)); Events.Add(new("calm", Position, 1000));
        }
    }
    public bool Interact()
    {
        if (Mode != VoyageMode.Sailing) return false;
        if (World.HarborAt(Position) != null) { Mode = VoyageMode.Harbor; Velocity = Vector2.Zero; SellCatch(); return true; }
        var fish = World.FishAt(Position);
        if (fish == null) return false;
        FishingPlace = fish; Mode = VoyageMode.Fishing; FishingTime = 0;
        fishRandom = new(SeedRandom.Hash(World.Seed, OceanWorld.KeyAt(fish.Position).X, OceanWorld.KeyAt(fish.Position).Y, fish.Style ^ (uint)World.Depletion.GetValueOrDefault(fish.Id)));
        World.Depletion[fish.Id] = 1; // One cast per school, including a cancelled attempt.
        FishCursor = .5f; FishTarget = fishRandom.Range(.25f, .75f); Events.Add(new("cast", fish.Position)); return true;
    }
    public void Reel()
    {
        if (Mode != VoyageMode.Fishing || FishingTime < .25f) return;
        bool success = Math.Abs(FishCursor - FishTarget) < FishBand;
        if (success) Events.Add(new("reel", Position));
        FinishFishing(success);
    }
    void FinishFishing(bool success)
    {
        if (FishingPlace == null) return;
        if (success)
        {
            string[] names = ["Silver sprat", "Coral snapper", "Moonfin tuna", "Golden lanternfish", "Abyssal stargazer"];
            int rarity = Math.Min(4, Tier + (fishRandom.Unit() > .7f ? 1 : 0));
            var item = new CatchItem(names[rarity], 14 + rarity * 13 + Tier * 4); Hold.Add(item);
            CatchTitle = item.Name;
            Events.Add(new("catch", Position, item.Value));
        }
        else { CatchTitle = "Got away"; Events.Add(new("miss", Position)); }
        FishingPlace = null;
        Mode = VoyageMode.Sailing;
    }
    public void CancelFishing() { if (Mode == VoyageMode.Fishing) { FishingPlace = null; Mode = VoyageMode.Sailing; } }
    public int LastCatchSale { get; private set; }
    void SellCatch()
    {
        int value = Hold.Sum(f => f.Value); LastCatchSale = value; Coins += value; Hold.Clear(); if (value > 0) Events.Add(new("sold", Position, value));
    }
    public int RepairCost => (int)MathF.Ceiling((MaxHealth - Health) / 3);
    public bool Repair()
    {
        if (Mode != VoyageMode.Harbor || RepairCost <= 0 || Coins < RepairCost) return false;
        Coins -= RepairCost; Health = MaxHealth; Events.Add(new("buy", Position)); return true;
    }
    void UpdateAbility(float dt)
    {
        if (Boat != BoatKind.Trawler) return;
        AbilityCharge += dt / 6;
        if (AbilityCharge < 1) return;
        AbilityCharge -= 1;
        Events.Add(new("bulwark", Position, 270));
        foreach (var shot in Shots) if (shot.Hostile && Vector2.Distance(shot.Position, Position) < 270) shot.Life = 0;
        foreach (var e in Enemies)
            if (e.Health > 0 && Vector2.Distance(e.Position, Position) < 270 + e.Radius)
                e.Position = World.Slide(e.Position, e.Position + OceanWorld.Unit(e.Position - Position) * 65, e.Radius);
    }
    void PrepareNextUpgrade()
    {
        UpgradeChoices.Clear();
        if (PendingUpgrades == 0) { Mode = VoyageMode.Sailing; return; }
        RollUpgrades(); Mode = VoyageMode.Upgrade;
    }
    public void TakeUpgradeGold()
    {
        if (Mode != VoyageMode.Upgrade || PendingUpgrades == 0 || UpgradeChoices.Count > 0) return;
        Coins += 40; PendingUpgrades--; PrepareNextUpgrade();
    }
    void RollUpgrades()
    {
        UpgradeChoices.Clear();
        var available = Enumerable.Range(0, UpgradeNames.Length).Where(CanUpgrade).ToList();
        // A weapon is always offered while one can still improve; remaining choices vary by seed/run.
        var weapons = available.Where(i => i < Weapons.Length).ToArray();
        if (weapons.Length > 0) { int first = weapons[buildRandom.Index(weapons.Length)]; UpgradeChoices.Add(first); available.Remove(first); }
        while (UpgradeChoices.Count < 3 && available.Count > 0) { int i = buildRandom.Index(available.Count); UpgradeChoices.Add(available[i]); available.RemoveAt(i); }
    }
    public int Rank(int option) => option < 6 ? Weapons[option] : option == 6 ? HullRank : option == 7 ? EngineRank : option == 8 ? ReloadRank : AreaRank;
    public bool CanUpgrade(int option) => option >= 0 && option < UpgradeNames.Length && Rank(option) < 5
        && (option >= Weapons.Length || Rank(option) > 0 || WeaponCount < WeaponSlots);
    public static bool SellsWeapons(Place harbor) => (harbor.Style & 1) == 0;
    public bool HarborSellsWeapons => World.HarborAt(Position) is { } harbor && SellsWeapons(harbor);
    public int[] HarborOffers()
    {
        return World.HarborAt(Position) is { } harbor ? HarborOffers(harbor) : [];
    }
    public static int[] HarborOffers(Place harbor)
    {
        var stock = Enumerable.Range(SellsWeapons(harbor) ? 0 : 6, SellsWeapons(harbor) ? 6 : 4).ToList();
        var random = new SeedRandom(harbor.Style ^ 0x51a7u);
        for (int i = stock.Count - 1; i > 0; i--)
        {
            int j = random.Index(i + 1);
            (stock[i], stock[j]) = (stock[j], stock[i]);
        }
        return stock.Take(3).ToArray();
    }
    public int UpgradeCost(int option) => 26 + Rank(option) * 22;
    public bool Upgrade(int option, bool free = false)
    {
        if (!CanUpgrade(option) || (free ? Mode != VoyageMode.Upgrade || !UpgradeChoices.Contains(option) : Mode != VoyageMode.Harbor)) return false;
        if (!free && (!HarborOffers().Contains(option) || Coins < UpgradeCost(option))) return false;
        if (!free) Coins -= UpgradeCost(option);
        if (option < 6) Weapons[option]++;
        else if (option == 6) HullRank++;
        else if (option == 7) EngineRank++;
        else if (option == 8) ReloadRank++;
        else AreaRank++;
        if (free) { PendingUpgrades--; PrepareNextUpgrade(); }
        Events.Add(new("buy", Position)); return true;
    }
    public static readonly string[] UpgradeNames = ["Cannon", "Harpoon", "Mines", "Lightning", "Whirlpool", "Arcane Orbs", "Hull", "Speed", "Reload", "Reach"];
    public static readonly string[] UpgradeDescriptions = [
        "Cannonballs bounce between foes and off rocks.",
        "Pierces enemies and pulls them closer.",
        "Drops mines behind you as you sail.",
        "Lightning jumps from enemy to enemy.",
        "A damaging ring around your boat.",
        "Magic orbs chase nearby enemies.",
        "Take more hits.",
        "Outrun trouble.",
        "Keep every weapon firing.",
        "Catch more enemies in each attack."];
    public string UpgradeBenefit(int option)
    {
        int rank = Rank(option);
        if (rank >= 5) return "Max level.";
        return option switch
        {
            0 => rank == 0 ? "Fires a bouncing cannonball." : $"Another cannonball. {rank + 1} per shot.",
            1 => rank == 0 ? "Hooks enemies and pulls them closer." : "Harpoon pulls harder. +160 pull speed.",
            2 => rank == 0 ? "Leaves explosive mines in your wake." : "Bigger mine blasts. +30 blast radius.",
            3 => rank == 0 ? "Lightning hits up to 3 enemies." : $"One more lightning target. {rank + 3} total.",
            4 => rank == 0 ? "Hits nearby enemies in every direction." : "Bigger whirlpool. +30 radius.",
            5 => rank == 0 ? "Fires a homing magic orb." : $"Another magic orb. {rank + 1} per cast.",
            6 => "+25 max health.",
            7 => "+10% sailing speed.",
            8 => "+12% fire rate for every weapon.",
            _ => "+15% attack area."
        };
    }

}

public sealed record BoatSpec(string Name, float Hull, float Speed, string Ability, string Description)
{
    public static readonly BoatSpec[] All = [
        new("Gunboat", 100, 235, "RAPID FIRE", "Fire 65% faster while boosting. Starts with bouncing cannonballs."),
        new("Aura", 155, 185, "DEFENSIVE PULSE", "Every 6s, clear nearby shots and push foes away. Starts with Whirlpool."),
        new("Mage", 115, 215, "HOMING MAGIC", "Magic orbs chase enemies for you. Starts with Arcane Orbs.")
    ];
    public static BoatSpec For(BoatKind kind) => All[(int)kind];
}
