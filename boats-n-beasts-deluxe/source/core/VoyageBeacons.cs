using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed class Beacon(string name, Vector2 position, EnemyKind guard)
{
    public const float Radius = 255;
    public const float ChargeSeconds = 17;
    public string Name { get; } = name;
    public Vector2 Position { get; } = position;
    public EnemyKind Guard { get; } = guard;
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
            new("Breakwater", FindWater(new(1250 + chart.Range(0, 210), -235 + chart.Range(-110, 65)), new(1050, -135)), EnemyKind.Puffer),
            new("Gull Shoal", FindWater(new(70 + chart.Range(-260, 260), 1350 + chart.Range(0, 280)), new(230, 800)), EnemyKind.Ray),
            new("Smuggler’s Light", FindWater(new(-1330 - chart.Range(0, 250), 245 + chart.Range(-130, 140)), new(-785, 110)), EnemyKind.Serpent)
        ];
    }

    void UpdateBeacons(float dt)
    {
        if (BossSpawned) return;
        var beacon = TargetBeacon;
        if (beacon == null || Vector2.DistanceSquared(Position, beacon.Position) > Beacon.Radius * Beacon.Radius) return;

        float before = beacon.Charge;
        beacon.Charge = Math.Min(Beacon.ChargeSeconds, beacon.Charge + dt);
        if (before == 0 || (before < 8 && beacon.Charge >= 8))
            SpawnBeaconGuard(beacon, before == 0 ? 0 : 1);
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
