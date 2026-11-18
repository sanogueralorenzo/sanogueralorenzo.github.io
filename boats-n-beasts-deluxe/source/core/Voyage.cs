using System.Numerics;
namespace BoatsNBeasts.Core;

public enum VoyageMode { Sailing, Upgrade, Paused, Defeat, Victory }
public enum BoatKind { Cutter, Trawler, Mage }
public enum EnemyKind { Crab, Puffer, Serpent, Ray, Leviathan }
public enum WeaponKind { Cannon, Harpoon, Mine, Coil, Undertow, Arcane }
public sealed class Enemy
{
    public int Id; public EnemyKind Kind; public Vector2 Position, Direction;
    public float Health, MaxHealth, Time, AttackClock, Telegraph, Dash, HitFlash, Pull, Fuse;
    public float SpeedMultiplier = 1;
    public bool ChargeNext;
    public float Exposed, Drenched;
    public Shot? PullMine;
    public Vector2? GuardAnchor;
    public const float PufferFuseDuration = 1.05f, PufferTriggerRadius = 125, PufferBlastRadius = 155;
    public const float EmergenceDuration = .45f;
    public bool Emerging => Time < EmergenceDuration;
    public float Radius => Kind == EnemyKind.Leviathan ? 74 : GuardAnchor.HasValue ? 43 : Kind == EnemyKind.Serpent ? 31 : 27;
    public float SwimSpeed => (Kind == EnemyKind.Crab ? 83 : Kind == EnemyKind.Puffer ? 105
        : Kind == EnemyKind.Serpent ? 111 : Kind == EnemyKind.Ray ? 135 : 73) * SpeedMultiplier;
}
public sealed class Shot
{
    public Vector2 Position, Previous, Velocity, Target;
    public float Damage, Life, Radius, Age, FlightDuration; public bool Hostile;
    public WeaponKind Kind; public int Pierce, Bounces;
    public bool Ricocheted, ComboSpent;
    public HashSet<int> Hit = new();
}
public readonly record struct GameEvent(string Kind, Vector2 Position, float Value = 0, Vector2 End = default);
public readonly record struct SailInput(Vector2 Move, bool Boost, bool Maneuver = false);
public sealed partial class Voyage
{
    public OceanWorld World { get; }
    public SeedRandom Random;
    SeedRandom buildRandom;
    int silver;
    public int SilverEarned => (int)(silver * Rules.SilverFactor);
    public Charter Charter { get; }
    public CharterRules Rules { get; }
    public SpawnDirector Director { get; } = new();
    public VoyageMode Mode = VoyageMode.Sailing;
    public bool IsActive => Mode == VoyageMode.Sailing;
    public BoatKind Boat { get; }
    public Vector2 Position, Velocity;
    public float Heading, Health, Boost = 100, CombatTime, Invulnerable, Distance, MaxDistance;
    public int Kills, Level = 1, Xp, HullRank, EngineRank, ReloadRank, AreaRank;
    public float FireRateMultiplier => Boat == BoatKind.Cutter && IsBoosting ? 1.65f : 1;
    public readonly List<int> UpgradeChoices = new();
    public bool BossSpawned, BossSlain;
    public bool BoostExhausted { get; private set; }
    public const int WeaponSlots = 3;
    public int WeaponCount => Weapons.Count(rank => rank > 0);
    public readonly int[] Weapons = new int[6];
    public readonly float[] Cooldowns = new float[6];
    public readonly List<Enemy> Enemies = new();
    public readonly List<Shot> Shots = new();
    public readonly List<GameEvent> Events = new();
    public int NextEnemyId;
    public int PufferExplosions, PufferBlastHits;
    public int BossBombsThrown, BossExplosions, BossBlastHits;
    public BoatSpec Spec => BoatSpec.For(Boat);
    public float MaxHealth => Spec.Hull * Rules.HullFactor + HullRank * 25;
    public float Speed => Spec.Speed * (1 + EngineRank * .1f);
    public int PendingUpgrades { get; private set; }
    public float WhirlpoolRadius => (154 + Math.Max(0, Weapons[4] - 1) * 30) * Area;
    public int NextXp => 5 + Level * 3;
    public float Area => 1 + AreaRank * .15f;
    public Voyage(uint seed, BoatKind boat, Charter charter = Charter.Coastguard)
    {
        World = new(seed);
        Random = new(seed ^ 0xa129f);
        buildRandom = new(seed ^ 0x77291);
        Boat = boat;
        Charter = charter;
        Rules = CharterRules.For(charter);
        Health = MaxHealth;
        Weapons[boat == BoatKind.Cutter ? 0 : boat == BoatKind.Trawler ? 4 : 5] = 1;
        Position = StartingArea.Spawn;
        Heading = MathF.PI;
        World.Stream(Position);
        Beacons = MakeBeacons(seed);
        Salvage = new(World.SalvageWreck);
    }
    public void Tick(float dt, SailInput input)
    {
        dt = Math.Clamp(dt, 0, .05f);
        if (!IsActive || dt <= 0) return;
        if (!BossSlain) CombatTime += dt;
        Invulnerable = Math.Max(0, Invulnerable - dt);
        UpdateMovement(dt, input);
        if (BossSlain) return;
        if (input.Maneuver && Boat == BoatKind.Mage && input.Move != Vector2.Zero && ManeuverCooldown <= dt)
            Heading = MathF.Atan2(input.Move.X, -input.Move.Y);
        UpdateManeuver(dt, input.Maneuver);
        if (!BossSlain) AdvanceEncounters(dt);
        Enemies.RemoveAll(e => e.Health <= 0 || (e.Kind != EnemyKind.Leviathan && e.GuardAnchor == null && Vector2.DistanceSquared(e.Position, Position) > 1600 * 1600));
        Shots.RemoveAll(s => s.Life <= 0);
        if (Mode == VoyageMode.Victory) return;
        if (Health <= 0) { Health = 0; Mode = VoyageMode.Defeat; Events.Add(new("defeat", Position)); }
        else
        {
            while (Xp >= NextXp) { Xp -= NextXp; Level++; PendingUpgrades++; Events.Add(new("level", Position)); }
            if (PendingUpgrades > 0) PrepareNextUpgrade();
        }
    }
    void AdvanceEncounters(float dt)
    {
        CollectEncounters();
        UpdateChain(dt);
        UpdateSalvage(dt);
        UpdateBeacons(dt);
        int spawn = Director.Tick(dt, CombatTime, Enemies.Count(e => e.Kind != EnemyKind.Leviathan), BossSpawned);
        for (int i = 0; i < spawn; i++) Spawn();
        if (!BossSpawned && (CombatTime >= SpawnDirector.BossArrivalSeconds || BeaconsLit == Beacons.Count))
        {
            if (Spawn(EnemyKind.Leviathan))
            {
                BossSpawned = true;
                Salvage.Towing = false;
                foreach (var escort in Enemies.Where(e => e.Kind != EnemyKind.Leviathan && e.Health > 0).OrderBy(e => Vector2.DistanceSquared(e.Position, Position)).Skip(SpawnDirector.BossEscortCount)) escort.Health = 0;
                Events.Add(new("boss", Enemies[^1].Position));
            }
        }
        UpdateEnemies(dt);
        if (BossSlain) return;
        UpdateWeapons(dt);
        if (BossSlain) return;
        UpdateShots(dt);
    }
    static float ApproachAngle(float from, float to, float amount) => from + MathF.Atan2(MathF.Sin(to - from), MathF.Cos(to - from)) * Math.Min(1, amount);
    public bool Spawn(EnemyKind? forced = null)
    {
        if (Enemies.Count >= 80) return false;
        var kind = forced ?? Director.Kind(CombatTime, Random.Unit());
        Vector2 p = default;
        for (int attempt = 0; attempt < 20; attempt++)
        {
            float angle = Random.Range(0, MathF.Tau);
            float distance = kind == EnemyKind.Leviathan ? Random.Range(445, 570) : Random.Range(530, 730);
            p = Position + new Vector2(MathF.Cos(angle), MathF.Sin(angle)) * distance;
            if (World.IsWater(p, 80)) break;
            if (attempt == 19) return false;
        }
        AddEnemy(kind, p);
        return true;
    }
    Enemy AddEnemy(EnemyKind kind, Vector2 position)
    {
        float hp = kind == EnemyKind.Leviathan ? 820 + 65 * BeaconsLit + Math.Min(300, CombatTime * .38f) : kind == EnemyKind.Crab ? 27 : kind == EnemyKind.Puffer ? 38 : kind == EnemyKind.Ray ? 43 : 52;
        hp *= Rules.EnemyHull;
        var enemy = new Enemy
        {
            Id = ++NextEnemyId, Kind = kind, Position = position, Health = hp, MaxHealth = hp,
            AttackClock = Random.Range(1, 3), SpeedMultiplier = Random.Range(.9f, 1.18f) * Rules.EnemySpeed
        };
        Enemies.Add(enemy);
        return enemy;
    }
    void UpdateEnemies(float dt)
    {
        // Pairwise separation keeps nearby silhouettes legible.
        foreach (var e in Enemies)
        {
            if (e.Health <= 0) continue;
            e.Time += dt;
            if (e.Emerging) continue;
            e.AttackClock -= dt; e.HitFlash = Math.Max(0, e.HitFlash - dt);
            e.Drenched = Math.Max(0, e.Drenched - dt);
            Vector2 d = Position - e.Position; float distance = d.Length(); Vector2 dir = OceanWorld.Unit(d, Vector2.UnitY);
            float speed = e.SwimSpeed;
            Vector2 motion = dir;
            if (e.GuardAnchor is { } anchor && Vector2.DistanceSquared(Position, anchor) > 605 * 605)
            {
                e.Telegraph = e.Dash = 0;
                var home = anchor - e.Position;
                var retreat = World.Avoid(e.Position, OceanWorld.Unit(home), e.Radius, e.Id);
                if (home.LengthSquared() > 80 * 80)
                    e.Position = World.Slide(e.Position, e.Position + retreat * speed * dt, e.Radius);
                continue;
            }
            if (e.Kind == EnemyKind.Puffer)
            {
                // Once armed, hold still and commit to the blast; sailing away avoids it.
                if (e.Fuse > 0)
                {
                    e.Fuse = Math.Max(0, e.Fuse - dt);
                    if (e.Fuse <= 0)
                    {
                        e.Health = 0;
                        PufferExplosions++;
                        Events.Add(new("pufferExplosion", e.Position, Enemy.PufferBlastRadius));
                        SplashEnemies(e.Position, Enemy.PufferBlastRadius, 24);
                        if (distance < Enemy.PufferBlastRadius + 23)
                        {
                            float before = Health;
                            DamagePlayer(22);
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
                // Weave toward the boat and attack by contact, never by firing.
                var side = new Vector2(-dir.Y, dir.X);
                motion = OceanWorld.Unit(dir + side * (.4f * MathF.Sin(e.Time * 2 + e.Id)));
            }
            if (e.Kind == EnemyKind.Leviathan)
            {
                bool enraged = e.Health < e.MaxHealth * .5f;
                e.Exposed = Math.Max(0, e.Exposed - dt);
                if (e.Telegraph > 0)
                {
                    e.Telegraph = Math.Max(0, e.Telegraph - dt);
                    motion = Vector2.Zero;
                    if (e.Telegraph == 0) e.Dash = .78f;
                }
                else if (e.Dash > 0)
                {
                    e.Dash = Math.Max(0, e.Dash - dt);
                    motion = e.Direction;
                    speed = 565;
                    if (e.Dash == 0) e.Exposed = 2.4f;
                }
                else if (e.AttackClock <= 0 && distance < 600)
                {
                    if (enraged && e.ChargeNext)
                    {
                        e.Telegraph = .9f;
                        e.Direction = dir;
                        motion = Vector2.Zero;
                    }
                    else
                    {
                        ThrowBossBombs(e);
                        e.Exposed = 1.8f;
                    }
                    e.ChargeNext = !e.ChargeNext;
                    e.AttackClock = enraged ? 3.6f : 4.6f;
                }
                else if (distance < 165) motion *= .25f;
                else if (distance > 430) speed *= 2.6f;
            }
            if (e.Dash > 0)
            {
                var next = e.Position + e.Direction * speed * dt;
                if (World.IsWater(next, e.Radius)) e.Position = next;
                else
                {
                    e.Dash = 0;
                    if (e.Kind == EnemyKind.Leviathan) e.Exposed = 2.4f;
                }
            }
            else
            {
                foreach (var other in Enemies)
                {
                    if (other == e || other.Health <= 0) continue;
                    var separation = e.Position - other.Position;
                    float span = separation.Length();
                    if (span > .1f && span < e.Radius + other.Radius) motion += separation / span * .65f;
                }
                if (e.Pull > 0) motion += HarpoonForce(e, dt) / speed;
                motion = World.Avoid(e.Position, motion, e.Radius, e.Id);
                e.Position = World.Slide(e.Position, e.Position + motion * speed * dt, e.Radius);
            }
            if (e.Kind != EnemyKind.Puffer && Vector2.DistanceSquared(e.Position, Position) < MathF.Pow(e.Radius + 23, 2)) DamagePlayer(e.Kind == EnemyKind.Leviathan ? 24 : e.GuardAnchor.HasValue ? 17 : 11);
        }
    }
    void ThrowBossBombs(Enemy boss)
    {
        var ahead = OceanWorld.Unit(Velocity, OceanWorld.Unit(Position - boss.Position));
        var across = new Vector2(-ahead.Y, ahead.X);
        int count = boss.Health < boss.MaxHealth * .5f ? 5 : 3;
        float sign = Random.Unit() < .5f ? -1 : 1;
        for (int i = 0; i < count && Shots.Count < 360; i++)
        {
            float flight = 1.05f + i * .15f;
            Vector2 target = i switch
            {
                0 => Position + Velocity * .72f,
                1 => Position + ahead * 280 + across * 155 * sign,
                2 => Position + ahead * 360 - across * 120 * sign,
                3 => Position + ahead * 510 + across * 95 * sign,
                _ => Position - ahead * 115 - across * 150 * sign
            };
            if (!World.IsWater(target, 22))
            {
                if (i > 0) continue;
                target = Position;
            }
            Shots.Add(new() { Hostile = true, Position = boss.Position, Previous = boss.Position,
                Target = target, Velocity = (target - boss.Position) / flight, FlightDuration = flight,
                Damage = 29, Life = flight, Radius = 153 });
            BossBombsThrown++;
        }
    }
    void DamagePlayer(float damage)
    {
        if (Invulnerable > 0 || !IsActive) return;
        Health -= damage; Invulnerable = .8f; Events.Add(new("hurt", Position, damage));
    }
    void Hit(Enemy e, float damage)
    {
        if (e.Kind == EnemyKind.Leviathan)
        {
            damage *= e.Exposed > 0 ? 1.22f : .50f;
            if (e.Health >= e.MaxHealth * .5f && e.Health - damage < e.MaxHealth * .5f)
            {
                e.AttackClock = Math.Min(e.AttackClock, 1.2f);
                e.ChargeNext = true;
                Events.Add(new("enraged", e.Position));
            }
        }
        e.Health -= damage; e.HitFlash = .12f; Events.Add(new("hit", e.Position, damage));
        if (e.Health > 0) return;
        Kills++;
        Xp += e.Kind switch { EnemyKind.Leviathan => 25, EnemyKind.Crab => 2, _ => 3 };
        ExtendChain(e.Position);
        if (Specialty == Specialty.Gunner) ManeuverCooldown = Math.Max(0, ManeuverCooldown - .8f);
        Events.Add(new("kill", e.Position, e.Kind == EnemyKind.Leviathan ? 2 : 1));
        if (e.Kind == EnemyKind.Puffer && e.Fuse > 0)
        {
            Events.Add(new("explosion", e.Position, Enemy.PufferBlastRadius));
            SplashEnemies(e.Position, Enemy.PufferBlastRadius, 24);
        }
        if (e.Kind == EnemyKind.Leviathan)
        {
            BossSlain = true; Mode = VoyageMode.Victory; silver += 6;
            // Mark dead/expired rather than mutate lists being traversed by the current attack.
            foreach (var other in Enemies) other.Health = 0;
            foreach (var shot in Shots) shot.Life = 0;
            Events.Add(new("victory", Position)); Events.Add(new("calm", Position, 1000));
        }
    }
    void SplashEnemies(Vector2 at, float radius, float damage)
    {
        foreach (var other in Enemies)
            if (other.Health > 0 && !other.Emerging && Vector2.DistanceSquared(other.Position, at) < radius * radius)
                Hit(other, damage);
    }
    void Heal(float amount)
    {
        float restored = Math.Min(amount, MaxHealth - Health);
        Health += restored;
        if (restored > 0) Events.Add(new("heal", Position, restored));
    }
    void PrepareNextUpgrade()
    {
        UpgradeChoices.Clear();
        if (PendingUpgrades == 0) { Mode = VoyageMode.Sailing; return; }
        RollUpgrades(); Mode = VoyageMode.Upgrade;
    }
    public void TakeUpgradeHeal()
    {
        if (Mode != VoyageMode.Upgrade || PendingUpgrades == 0 || UpgradeChoices.Count > 0) return;
        Heal(25); PendingUpgrades--; PrepareNextUpgrade();
    }
    void RollUpgrades()
    {
        UpgradeChoices.Clear();
        if (IsSpecialtyLevel)
        {
            UpgradeChoices.AddRange(Enumerable.Range(FirstSpecialtyOption, UpgradeNames.Length - FirstSpecialtyOption));
            return;
        }
        var available = Enumerable.Range(0, UpgradeNames.Length).Where(CanUpgrade).ToList();
        bool IsNewWeapon(int option) => option < Weapons.Length && Rank(option) == 0;
        int refitLevel = Level - PendingUpgrades + 1;
        bool pairingDraft = ActiveCombo == null && WeaponCount < WeaponSlots && refitLevel is 2 or 6;
        if (pairingDraft)
            AddChoice(available, option => IsNewWeapon(option) &&
                WeaponCombo.ForUpgrade(option) is { } combo && Rank(combo.Partner(option)) > 0);

        AddChoice(available, option => option < Weapons.Length && Rank(option) > 0);
        AddChoice(available, IsNewWeapon);
        if (UpgradeChoices.Count < 3) AddChoice(available, option => option >= Weapons.Length);
        while (UpgradeChoices.Count < 3 && available.Count > 0) AddChoice(available, _ => true);
    }
    void AddChoice(List<int> available, Func<int, bool> matches)
    {
        var candidates = available.Where(matches).ToArray();
        if (candidates.Length == 0) return;
        int option = candidates[buildRandom.Index(candidates.Length)];
        available.Remove(option);
        UpgradeChoices.Add(option);
    }
    public int Rank(int option) => option switch
    {
        < 6 => Weapons[option],
        6 => HullRank,
        7 => EngineRank,
        8 => ReloadRank,
        9 => AreaRank,
        _ => option == FirstSpecialtyOption + (int)Specialty - 1 ? 1 : 0
    };
    public bool CanUpgrade(int option)
    {
        if (option < 0 || option >= UpgradeNames.Length) return false;
        if (option >= FirstSpecialtyOption) return IsSpecialtyLevel && Specialty == Specialty.None;
        return Rank(option) < 5 && (option >= Weapons.Length || Rank(option) > 0 || WeaponCount < WeaponSlots);
    }
    public bool Upgrade(int option)
    {
        if (Mode != VoyageMode.Upgrade || PendingUpgrades == 0 || !UpgradeChoices.Contains(option) || !CanUpgrade(option)) return false;
        if (option < 6)
        {
            Weapons[option]++;
            var combo = WeaponCombo.ForUpgrade(option);
            if (Weapons[option] == 1 && combo != null && IsFitted(combo))
                Events.Add(new("comboFitted", Position));
        }
        else if (option == 6) { HullRank++; Heal(25); }
        else if (option == 7) EngineRank++;
        else if (option == 8) ReloadRank++;
        else if (option == 9) AreaRank++;
        else SelectSpecialty(option);
        PendingUpgrades--; PrepareNextUpgrade();
        Events.Add(new("upgrade", Position)); return true;
    }
    public static readonly string[] UpgradeNames = ["Cannon", "Harpoon", "Mines", "Lightning", "Whirlpool", "Arcane Orbs", "Hull", "Speed", "Reload", "Reach", "Windrunner", "Shipwright", "Master Gunner"];
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
        "Catch more enemies in each attack.",
        "Boost recovers 50% faster. Taking this upgrade fills it.",
        "Chains last 7 seconds. Every fourth kill in a chain repairs 10 hull.",
        "Each kill cuts 0.8s from your maneuver cooldown. Your maneuver is ready now."];
    public string UpgradeBenefit(int option)
    {
        int rank = Rank(option);
        if (rank >= 5) return "Max level.";
        return option switch
        {
            0 => rank == 0 ? "Fires a bouncing cannonball." : rank == 4 ? "Five cannonballs. Each can ricochet twice." : $"Another cannonball. {rank + 1} per shot.",
            1 => rank == 0 ? "Hooks enemies and pulls them closer." : rank == 4 ? "Pierces three beasts and pulls harder." : "Harpoon pulls harder and deals more damage.",
            2 => rank == 0 ? "Leaves explosive mines in your wake." : rank == 4 ? "Bigger blasts and faster mine deployment." : "Bigger mine blasts. +30 blast radius.",
            3 => rank == 0 ? "Lightning hits up to 3 enemies." : $"{rank + 3} targets and more damage.",
            4 => rank == 0 ? "Hits nearby enemies in every direction." : "Larger whirlpool and more damage.",
            5 => rank == 0 ? "Fires a homing magic orb." : rank == 4 ? "Five homing orbs. Each can strike twice." : $"Another magic orb. {rank + 1} per cast.",
            6 => "+25 max health and repairs 25 hull.",
            7 => "+10% sailing speed.",
            8 => "+12% fire rate for every weapon.",
            9 => "+15% attack area.",
            _ => UpgradeDescriptions[option]
        };
    }

}

public sealed record BoatSpec(string Name, float Hull, float Speed, string Maneuver, int ManeuverSeconds, string Description)
{
    public static readonly BoatSpec[] All = [
        new("Gunboat", 110, 235, "Broadside", 12, "Fire a fan of ricocheting cannonballs from both sides. Boosting reloads weapons faster."),
        new("Trawler", 155, 200, "Breakwater", 14, "Send out a shockwave that damages and shoves beasts, clears bombs, and briefly shields the boat."),
        new("Mage", 125, 228, "Slipstream", 8, "Blink forward through beasts, leaving a damaging wake. Your starting orbs track nearby targets.")
    ];
    public static BoatSpec For(BoatKind kind) => All[(int)kind];
}
