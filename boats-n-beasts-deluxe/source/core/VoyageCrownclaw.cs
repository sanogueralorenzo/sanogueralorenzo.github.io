using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed partial class Voyage
{
    public const float HuntSignalDuration = 2.6f;
    public const float BombOpening = 1.8f;
    public const float ChargeOpening = 2.25f;
    public const float GroundedOpening = 3.75f;
    const float CrownclawRange = 490, CrownclawSpeed = 565;

    public Beacon? HuntSignalBeacon { get; private set; }
    public float HuntSignalRemaining { get; private set; }
    public bool HuntSignalReady => BeaconsLit == 2 && !BossSpawned && HuntSignalBeacon == null && !Salvage.Towing;
    public bool CrownclawArmorWeakened => BeaconsLit == Beacons.Count;
    public Beacon? NearbySignalBeacon => HuntSignalReady ? Beacons.FirstOrDefault(beacon =>
        beacon.Lit && Vector2.DistanceSquared(Position, beacon.Position) <= Beacon.Radius * Beacon.Radius) : null;

    public bool TrySignalCrownclaw()
    {
        if (!IsActive || NearbySignalBeacon is not { } beacon) return false;
        HuntSignalBeacon = beacon;
        HuntSignalRemaining = HuntSignalDuration;
        Events.Add(new("huntSignal", beacon.Position));
        return true;
    }

    void UpdateCrownclawArrival(float dt)
    {
        if (BossSpawned) return;
        HuntSignalRemaining = Math.Max(0, HuntSignalRemaining - dt);
        bool signalFinished = HuntSignalBeacon != null && HuntSignalRemaining <= 0;
        if (!signalFinished && !CrownclawArmorWeakened && CombatTime < SpawnDirector.BossArrivalSeconds) return;
        if (!Spawn(EnemyKind.Leviathan)) return;

        BossSpawned = true;
        HuntSignalRemaining = 0;
        Salvage.Towing = false;
        FloatingCache = null;
        foreach (var escort in Enemies.Where(enemy => enemy.Kind != EnemyKind.Leviathan && enemy.Health > 0)
            .OrderBy(enemy => Vector2.DistanceSquared(enemy.Position, Position)).Skip(SpawnDirector.BossEscortCount))
            escort.Health = 0;
        Events.Add(new("boss", Enemies[^1].Position));
    }

    bool UpdateCrownclaw(Enemy boss, float dt, float distance, Vector2 toward, ref Vector2 motion, ref float speed)
    {
        boss.Exposed = Math.Max(0, boss.Exposed - dt);
        if (boss.Grounded)
        {
            if (boss.Exposed > 0) return true;
            boss.Grounded = false;
        }
        if (boss.Charge is { } charge)
        {
            if (charge.Advance(boss, dt))
            {
                boss.Grounded = charge.HitsCoast;
                boss.Exposed = boss.Grounded ? GroundedOpening : ChargeOpening;
                if (boss.Grounded)
                {
                    boss.AttackClock = GroundedOpening + .6f;
                    Events.Add(new("crownclawGrounded", boss.Position, 155));
                }
            }
            return true;
        }

        bool enraged = boss.Health < boss.MaxHealth * .5f;
        float reach = boss.ChargeNext ? CrownclawRange + boss.ContactRadius * .5f : 600;
        if (boss.AttackClock <= 0 && distance < reach)
        {
            boss.AttackClock = enraged ? 3.6f : 4.6f;
            boss.ChargeNext = !boss.ChargeNext;
            if (boss.ChargeNext)
            {
                ThrowBossBombs(boss);
                boss.Exposed = BombOpening;
            }
            else
            {
                float windup = enraged ? .84f : 1.15f;
                boss.Direction = toward;
                boss.Charge = BeastCharge.Aim(World, boss.Position, toward, boss.Radius,
                    windup, CrownclawRange, CrownclawSpeed);
                boss.Exposed = 0;
                boss.Telegraph = windup;
                Events.Add(new("crownclawWindup", boss.Position));
                return true;
            }
        }
        if (distance < 165) motion *= .25f;
        else if (distance > 400) speed *= 2.6f;
        return false;
    }

    void ThrowBossBombs(Enemy boss)
    {
        int before = BossBombsThrown;
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
        if (BossBombsThrown > before) Events.Add(new("bossVolley", boss.Position));
    }
}
