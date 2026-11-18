using System.Numerics;
namespace BoatsNBeasts.Core;

public enum BeaconObjective { Defend, Patrol, Duel }

public sealed class Beacon(string name, Vector2 position, EnemyKind guard, BeaconObjective objective)
{
    public const float Radius = 255;
    public const float ChargeSeconds = 17;
    public string Name { get; } = name;
    public Vector2 Position { get; } = position;
    public EnemyKind Guard { get; } = guard;
    public BeaconObjective Objective { get; } = objective;
    public bool Started { get; internal set; }
    public Enemy? Keeper { get; internal set; }
    public float Progress => Objective == BeaconObjective.Duel && Keeper is { } keeper && !Lit
        ? 1 - Math.Clamp(keeper.Health / keeper.MaxHealth, 0, 1)
        : Charge / ChargeSeconds;
    public string Order => Objective switch
    {
        BeaconObjective.Patrol => "Sail inside the ring",
        BeaconObjective.Duel => "Defeat the keeper",
        _ => "Hold the ring"
    };
    public float Charge { get; internal set; }
    public bool Lit => Charge >= ChargeSeconds;
}

public sealed partial class Voyage
{
    public IReadOnlyList<Beacon> Beacons { get; }
    public int BeaconsLit { get; private set; }
    public int LongestChain { get; private set; }
    public int Chain { get; private set; }
    public float ChainTime { get; private set; }
    public Beacon? TargetBeacon => Beacons.Where(b => !b.Lit)
        .MinBy(b => Vector2.DistanceSquared(b.Position, Position));

    IReadOnlyList<Beacon> MakeBeacons(uint seed)
    {
        var chart = new SeedRandom(seed ^ 0xd6c309ebu);
        Vector2 FindWater(Vector2 candidate, Vector2 fallback)
        {
            for (int step = 0; step < 7; step++)
            {
                var point = Vector2.Lerp(candidate, fallback, step / 6f);
                if (World.IsWater(point, Beacon.Radius + 42)) return point;
            }
            return fallback;
        }

        return
        [
            new("Breakwater", FindWater(new(1250 + chart.Range(0, 210), -235 + chart.Range(-110, 65)), new(1050, -135)), EnemyKind.Puffer, BeaconObjective.Defend),
            new("Gull Shoal", FindWater(new(70 + chart.Range(-260, 260), 1350 + chart.Range(0, 280)), new(230, 800)), EnemyKind.Ray, BeaconObjective.Patrol),
            new("Smuggler’s Light", FindWater(new(-1330 - chart.Range(0, 250), 245 + chart.Range(-130, 140)), new(-785, 110)), EnemyKind.Serpent, BeaconObjective.Duel)
        ];
    }

    void UpdateBeacons(float dt)
    {
        if (BossSpawned) return;

        var beacon = Beacons.FirstOrDefault(b => !b.Lit && b.Keeper is { Health: <= 0 });
        if (beacon != null) beacon.Charge = Beacon.ChargeSeconds;
        else
        {
            beacon = TargetBeacon;
            if (beacon == null || Vector2.DistanceSquared(Position, beacon.Position) > Beacon.Radius * Beacon.Radius) return;
            if (!beacon.Started)
            {
                beacon.Started = true;
                SpawnBeaconGuard(beacon, 0);
                if (beacon.Objective == BeaconObjective.Duel)
                {
                    var direction = OceanWorld.Unit(beacon.Position - Position, Vector2.UnitY);
                    var anchor = beacon.Position + direction * 175;
                    if (!World.IsWater(anchor, 48)) anchor = beacon.Position;
                    var keeper = AddEnemy(beacon.Guard, anchor);
                    keeper.GuardAnchor = beacon.Position;
                    keeper.Health = keeper.MaxHealth = (155 + 70 * BeaconsLit) * Rules.EnemyHull;
                    beacon.Keeper = keeper;
                }
            }
            if (beacon.Objective == BeaconObjective.Duel) return;
            if (beacon.Objective == BeaconObjective.Patrol && Velocity.LengthSquared() < Speed * Speed * .24f) return;

            float before = beacon.Charge;
            beacon.Charge = Math.Min(Beacon.ChargeSeconds, beacon.Charge + dt);
            if (before < 8 && beacon.Charge >= 8) SpawnBeaconGuard(beacon, 1);
        }

        if (!beacon.Lit) return;

        BeaconsLit++;
        int xp = 10 + 3 * (BeaconsLit - 1);
        Xp += xp;
        Heal(15);
        Boost = 100;
        silver += 2;
        Events.Add(new("beacon", beacon.Position, xp));
    }

    void SpawnBeaconGuard(Beacon beacon, int wave)
    {
        Events.Add(new("beaconStart", beacon.Position, Beacon.Radius));
        int count = 2 + wave + BeaconsLit;
        float phase = Random.Range(0, MathF.Tau);
        for (int i = 0; i < count; i++)
        {
            float angle = phase + MathF.Tau * i / count;
            var direction = new Vector2(MathF.Cos(angle), MathF.Sin(angle));
            var anchor = beacon.Position + direction * 332;
            if (!World.IsWater(anchor, 57)) anchor = beacon.Position + direction * 252;
            if (!World.IsWater(anchor, 57)) continue;
            var kind = wave == 0 && i == 0 ? EnemyKind.Crab : beacon.Guard;
            AddEnemy(kind, anchor);
        }
    }

    void UpdateChain(float dt)
    {
        ChainTime = Math.Max(0, ChainTime - dt);
        if (ChainTime == 0) Chain = 0;
    }

    void ExtendChain(Vector2 at)
    {
        Chain++;
        ChainTime = ChainDuration;
        LongestChain = Math.Max(LongestChain, Chain);
        if (Chain % 4 != 0) return;
        Xp += 3;
        Boost = Math.Min(100, Boost + 28);
        silver++;
        if (Specialty == Specialty.Shipwright) Heal(10);
        Events.Add(new("chain", at, Chain));
    }
}
