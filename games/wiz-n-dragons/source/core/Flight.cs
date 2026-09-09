using System.Numerics;
namespace WizNDragons.Core;

public enum FlightMode { Flying, Upgrade, Paused, Defeat, Victory }
public enum WizardKind { Ember, Warden, Mage }
public enum EnemyKind { Imp, Spark, Drake, Wyrm, ElderDragon }
public enum SpellKind { Fireball, Tether, Rune, Lightning, Aura, Arcane }
public sealed class Enemy
{
    public int Id; public EnemyKind Kind; public Vector2 Position, Direction;
    public float Health, MaxHealth, Time, AttackClock, Telegraph, Dash, HitFlash, Pull, Fuse;
    public float SpeedMultiplier = 1;
    public const float SparkFuseDuration = 1.05f, SparkTriggerRadius = 125, SparkBlastRadius = 155;
    public const float EmergenceDuration = .45f;
    public bool Emerging => Time < EmergenceDuration;
    public float Radius => Kind == EnemyKind.ElderDragon ? 74 : Kind == EnemyKind.Drake ? 31 : 27;
    public float FlightSpeed => (Kind == EnemyKind.Imp ? 83 : Kind == EnemyKind.Spark ? 105
        : Kind == EnemyKind.Drake ? 111 : Kind == EnemyKind.Wyrm ? 135 : 73) * SpeedMultiplier;
}
public sealed class Shot
{
    public Vector2 Position, Previous, Velocity, Target;
    public float Damage, Life, Radius, Age, FlightDuration; public bool Hostile;
    public SpellKind Kind; public int Pierce, Bounces;
    public HashSet<int> Hit = new();
}
public readonly record struct GameEvent(string Kind, Vector2 Position, float Value = 0, Vector2 End = default);
public readonly record struct FlightInput(Vector2 Move, bool Boost);
public sealed partial class Flight
{
    public SkyWorld World { get; }
    public SeedRandom Random;
    SeedRandom buildRandom;
    readonly System.Random silverRandom = new();
    public int SilverEarned { get; private set; }
    public float NextSilverTime { get; private set; }
    float SilverInterval() => 45 + silverRandom.NextSingle() * 45;
    public SpawnDirector Director { get; } = new();
    public FlightMode Mode = FlightMode.Flying;
    public bool IsActive => Mode == FlightMode.Flying;
    public WizardKind Wizard { get; }
    public Vector2 Position, Velocity;
    public float Heading, Health, Boost = 100, CombatTime, Invulnerable, Distance, MaxDistance;
    public int Kills, Level = 1, Xp, VitalityRank, HasteRank, FocusRank, AreaRank;
    public float AbilityCharge;
    public float FireRateMultiplier => Wizard == WizardKind.Ember && IsBoosting ? 1.65f : 1;
    public readonly List<int> UpgradeChoices = new();
    public bool BossSpawned, BossSlain;
    public bool BoostExhausted { get; private set; }
    public const int BaseSpellSlots = 2, MaxSpellSlots = 5;
    public int SpellSlots { get; }
    public int SpellCount => Spells.Count(rank => rank > 0);
    public readonly int[] Spells = new int[6];
    public readonly float[] Cooldowns = new float[6];
    public readonly List<Enemy> Enemies = new();
    public readonly List<Shot> Shots = new();
    public readonly List<GameEvent> Events = new();
    public int NextEnemyId;
    public int SparkExplosions, SparkBlastHits;
    public int BossBombsThrown, BossExplosions, BossBlastHits;
    public WizardSpec Spec => WizardSpec.For(Wizard);
    public float MaxHealth => Spec.Vitality + VitalityRank * 25;
    public float Speed => Spec.Speed * (1 + HasteRank * .1f);
    public int PendingUpgrades { get; private set; }
    public float WardRadius => (138 + Math.Max(0, Spells[4] - 1) * 30) * Area;
    public int NextXp => 7 + Level * 5;
    public float Area => 1 + AreaRank * .15f;
    public Flight(uint seed, WizardKind wizard, int extraSpellSlots = 0)
    {
        World = new(seed); Random = new(seed ^ 0xa129f); buildRandom = new(seed ^ 0x77291); Wizard = wizard; Health = MaxHealth;
        SpellSlots = BaseSpellSlots + Math.Clamp(extraSpellSlots, 0, MaxSpellSlots - BaseSpellSlots);
        Spells[wizard == WizardKind.Ember ? 0 : wizard == WizardKind.Warden ? 4 : 5] = 1;
        NextSilverTime = SilverInterval();
        Position = Vector2.Zero;
        Heading = MathF.PI;
        World.Stream(Position);
    }
    public void Tick(float dt, FlightInput input)
    {
        dt = Math.Clamp(dt, 0, .05f);
        if (!IsActive) return;
        CombatTime += dt; Invulnerable = Math.Max(0, Invulnerable - dt);
        UpdateMovement(dt, input);
        CollectEncounters();
        int spawn = Director.Tick(dt, CombatTime, Enemies.Count(e => e.Kind != EnemyKind.ElderDragon), BossSpawned && !BossSlain);
        for (int i = 0; i < spawn; i++) Spawn();
        if (CombatTime >= SpawnDirector.BossArrivalSeconds && !BossSpawned)
        {
            if (Spawn(EnemyKind.ElderDragon))
            {
                BossSpawned = true;
                foreach (var escort in Enemies.Where(e => e.Kind != EnemyKind.ElderDragon && e.Health > 0).OrderBy(e => Vector2.DistanceSquared(e.Position, Position)).Skip(SpawnDirector.BossEscortCount)) escort.Health = 0;
                Events.Add(new("boss", Enemies[^1].Position));
            }
        }
        UpdateAbility(dt);
        UpdateEnemies(dt);
        UpdateSpells(dt);
        UpdateShots(dt);
        Enemies.RemoveAll(e => e.Health <= 0 || (e.Kind != EnemyKind.ElderDragon && Vector2.DistanceSquared(e.Position, Position) > 1600 * 1600));
        Shots.RemoveAll(s => s.Life <= 0);
        if (Mode == FlightMode.Victory) return;
        if (Health <= 0) { Health = 0; Mode = FlightMode.Defeat; Events.Add(new("defeat", Position)); }
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
        var kind = forced ?? Director.Kind(CombatTime, Random.Unit());
        float angle = Random.Range(0, MathF.Tau);
        var p = Position + new Vector2(MathF.Cos(angle), MathF.Sin(angle)) * Random.Range(760, 940);
        float hp = kind == EnemyKind.ElderDragon ? 1050 : kind == EnemyKind.Imp ? 27 : kind == EnemyKind.Spark ? 38 : kind == EnemyKind.Wyrm ? 43 : 52;
        Enemies.Add(new() { Id = ++NextEnemyId, Kind = kind, Position = p, Health = hp, MaxHealth = hp, AttackClock = Random.Range(1, 3), SpeedMultiplier = Random.Range(.85f, 1.4f) });
        return true;
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
            Vector2 d = Position - e.Position; float distance = d.Length(); Vector2 dir = SkyWorld.Unit(d, Vector2.UnitY);
            float speed = e.FlightSpeed;
            Vector2 motion = dir;
            if (e.Kind == EnemyKind.Spark)
            {
                // Once armed, hold still and commit to the blast; flying away avoids it.
                if (e.Fuse > 0)
                {
                    e.Fuse = Math.Max(0, e.Fuse - dt);
                    if (e.Fuse <= 0)
                    {
                        e.Health = 0;
                        SparkExplosions++;
                        Events.Add(new("sparkExplosion", e.Position, Enemy.SparkBlastRadius));
                        if (distance < Enemy.SparkBlastRadius + 23)
                        {
                            float before = Health;
                            DamagePlayer(22);
                            if (Health < before) SparkBlastHits++;
                        }
                    }
                    continue;
                }
                else if (distance <= Enemy.SparkTriggerRadius)
                {
                    e.Fuse = Enemy.SparkFuseDuration;
                    continue;
                }
            }
            if (e.Kind == EnemyKind.Drake)
            {
                if (e.AttackClock <= 0 && e.Dash <= 0) { e.Telegraph = .85f; e.Direction = dir; e.AttackClock = 4.3f; }
                if (e.Telegraph > 0) { e.Telegraph -= dt; motion *= .1f; if (e.Telegraph <= 0) e.Dash = .7f; }
                if (e.Dash > 0) { e.Dash -= dt; motion = e.Direction; speed *= 3.4f; }
            }
            if (e.Kind == EnemyKind.Wyrm)
            {
                // Weave toward the wizard and attack by contact, never by firing.
                var side = new Vector2(-dir.Y, dir.X);
                motion = SkyWorld.Unit(dir + side * (.4f * MathF.Sin(e.Time * 2 + e.Id)));
            }
            if (e.Kind == EnemyKind.ElderDragon)
            {
                if (distance > 1200) e.Position = Position - dir * 1000;
                if (e.AttackClock <= 0)
                {
                    ThrowBossBombs(e);
                    e.AttackClock = e.Health < e.MaxHealth * .5f ? 3.2f : 4.2f;
                }
                if (distance < 220) motion *= .2f;
            }
            foreach (var other in Enemies)
            {
                if (other == e || other.Health <= 0) continue;
                var sep = e.Position - other.Position; float len = sep.Length();
                if (len > .1f && len < e.Radius + other.Radius) motion += sep / len * .65f;
            }
            if (e.Pull > 0)
            {
                e.Pull = Math.Max(0, e.Pull - dt);
                if (distance > 110) motion += dir * ((320 + (Spells[1] - 1) * 160) / speed) * (e.Kind == EnemyKind.ElderDragon ? .25f : 1);
            }
            e.Position += motion * speed * dt;
            if (e.Kind != EnemyKind.Spark && distance < e.Radius + 23) DamagePlayer(e.Kind == EnemyKind.ElderDragon ? 24 : 11);
        }
    }
    void ThrowBossBombs(Enemy boss)
    {
        var center = Position;
        int count = boss.Health < boss.MaxHealth * .5f ? 4 : 3;
        float phase = Random.Range(0, MathF.Tau);
        for (int i = 0; i < count && Shots.Count < 360; i++)
        {
            var target = center;
            if (i > 0)
            {
                float angle = phase + (i - 1) * MathF.Tau / (count - 1);
                target += new Vector2(MathF.Cos(angle), MathF.Sin(angle)) * Random.Range(150, 240);
            }
            float flight = 1.25f + i * .18f;
            Shots.Add(new() { Hostile = true, Position = boss.Position, Previous = boss.Position,
                Target = target, Velocity = (target - boss.Position) / flight, FlightDuration = flight,
                Damage = 26, Life = flight, Radius = 140 });
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
        e.Health -= damage; e.HitFlash = .12f; Events.Add(new("hit", e.Position, damage));
        if (e.Health > 0) return;
        Kills++; Xp += e.Kind == EnemyKind.ElderDragon ? 25 : 1;
        // Schedule from this award so idle time cannot bank silver drops.
        if (CombatTime >= NextSilverTime)
        {
            SilverEarned++;
            NextSilverTime = CombatTime + SilverInterval();
            Events.Add(new("silver", e.Position));
        }
        Events.Add(new("kill", e.Position, e.Kind == EnemyKind.ElderDragon ? 2 : 1));
        if (e.Kind == EnemyKind.ElderDragon)
        {
            BossSlain = true; Mode = FlightMode.Victory;
            // Mark dead/expired rather than mutate lists being traversed by the current attack.
            foreach (var other in Enemies) other.Health = 0;
            foreach (var shot in Shots) shot.Life = 0;
            Events.Add(new("victory", Position)); Events.Add(new("calm", Position, 1000));
        }
    }
    void Heal(float amount)
    {
        float restored = Math.Min(amount, MaxHealth - Health);
        Health += restored;
        if (restored > 0) Events.Add(new("heal", Position, restored));
    }
    void UpdateAbility(float dt)
    {
        if (Wizard != WizardKind.Warden) return;
        AbilityCharge += dt / 6;
        if (AbilityCharge < 1) return;
        AbilityCharge -= 1;
        Events.Add(new("bulwark", Position, 270));
        foreach (var shot in Shots) if (shot.Hostile && Vector2.Distance(shot.Position, Position) < 270) shot.Life = 0;
        foreach (var e in Enemies)
            if (e.Health > 0 && Vector2.Distance(e.Position, Position) < 270 + e.Radius)
                e.Position += SkyWorld.Unit(e.Position - Position) * 65;
    }
    void PrepareNextUpgrade()
    {
        UpgradeChoices.Clear();
        if (PendingUpgrades == 0) { Mode = FlightMode.Flying; return; }
        RollUpgrades(); Mode = FlightMode.Upgrade;
    }
    public void TakeUpgradeHeal()
    {
        if (Mode != FlightMode.Upgrade || PendingUpgrades == 0 || UpgradeChoices.Count > 0) return;
        Heal(25); PendingUpgrades--; PrepareNextUpgrade();
    }
    void RollUpgrades()
    {
        UpgradeChoices.Clear();
        // Alternate categories, starting with spells; use the other when one is maxed.
        bool offerSpells = (Level - PendingUpgrades) % 2 == 1;
        var available = Enumerable.Range(0, UpgradeNames.Length)
            .Where(i => CanUpgrade(i) && (i < Spells.Length) == offerSpells).ToList();
        if (available.Count == 0)
            available = Enumerable.Range(0, UpgradeNames.Length)
                .Where(i => CanUpgrade(i) && (i < Spells.Length) != offerSpells).ToList();
        while (UpgradeChoices.Count < 3 && available.Count > 0) { int i = buildRandom.Index(available.Count); UpgradeChoices.Add(available[i]); available.RemoveAt(i); }
    }
    public int Rank(int option) => option < 6 ? Spells[option] : option == 6 ? VitalityRank : option == 7 ? HasteRank : option == 8 ? FocusRank : AreaRank;
    public bool CanUpgrade(int option) => option >= 0 && option < UpgradeNames.Length && Rank(option) < 5
        && (option >= Spells.Length || Rank(option) > 0 || SpellCount < SpellSlots);
    public bool Upgrade(int option)
    {
        if (Mode != FlightMode.Upgrade || PendingUpgrades == 0 || !UpgradeChoices.Contains(option) || !CanUpgrade(option)) return false;
        if (option < 6) Spells[option]++;
        else if (option == 6) VitalityRank++;
        else if (option == 7) HasteRank++;
        else if (option == 8) FocusRank++;
        else AreaRank++;
        PendingUpgrades--; PrepareNextUpgrade();
        Events.Add(new("upgrade", Position)); return true;
    }
    public static readonly string[] UpgradeNames = ["Fireball", "Tether", "Runes", "Lightning", "Ward", "Arcane Orbs", "Vitality", "Haste", "Focus", "Reach"];
    public static readonly string[] UpgradeDescriptions = [
        "Fireballs ricochet between nearby foes.",
        "Pierces enemies and pulls them closer.",
        "Leaves runes behind you as you fly.",
        "Lightning jumps from enemy to enemy.",
        "A damaging ring around your wizard.",
        "Magic orbs chase nearby enemies.",
        "Take more hits.",
        "Outrun trouble.",
        "Keep every spell firing.",
        "Catch more enemies in each attack."];
    public string UpgradeBenefit(int option)
    {
        int rank = Rank(option);
        if (rank >= 5) return "Max level.";
        return option switch
        {
            0 => rank == 0 ? "Casts a bouncing fireball." : $"Another fireball. {rank + 1} per cast.",
            1 => rank == 0 ? "Binds enemies and pulls them closer." : "Binding pulls harder. +160 pull speed.",
            2 => rank == 0 ? "Leaves explosive runes in your wake." : "Bigger rune blasts. +30 blast radius.",
            3 => rank == 0 ? "Lightning hits up to 3 enemies." : $"One more lightning target. {rank + 3} total.",
            4 => rank == 0 ? "Hits nearby enemies in every direction." : "Bigger ward. +30 radius.",
            5 => rank == 0 ? "Fires a homing magic orb." : $"Another magic orb. {rank + 1} per cast.",
            6 => "+25 max health.",
            7 => "+10% flying speed.",
            8 => "+12% fire rate for every spell.",
            _ => "+15% attack area."
        };
    }

}

public sealed record WizardSpec(string Name, float Vitality, float Speed, string Ability, string Description)
{
    public static readonly WizardSpec[] All = [
        new("Ember", 100, 305, "QUICKCAST", "Fire 65% faster while boosting. Starts with bouncing fireballs."),
        new("Warden", 155, 245, "WARD PULSE", "Every 6s, clear nearby shots and push foes away. Starts with Ward."),
        new("Arcanist", 115, 285, "HOMING MAGIC", "Magic orbs chase enemies for you. Starts with Arcane Orbs.")
    ];
    public static WizardSpec For(WizardKind kind) => All[(int)kind];
}
