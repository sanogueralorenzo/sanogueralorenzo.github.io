using System.Numerics;
namespace BoatsNBeasts.Core;

public readonly record struct CrownclawCharge(Vector2 Start, Vector2 End, float Windup, bool HitsCoast)
{
    public const float Range = 490;
    public const float Speed = 565;
    public float Duration => Vector2.Distance(Start, End) / Speed;

    public static CrownclawCharge Aim(OceanWorld world, Vector2 start, Vector2 direction, float clearance, float windup)
    {
        const float step = 8;
        float last = 0;
        for (int i = 1; i <= (int)MathF.Ceiling(Range / step); i++)
        {
            float distance = Math.Min(i * step, Range);
            var point = start + direction * distance;
            if (!world.IsWater(point, clearance))
            {
                for (int refinement = 0; refinement < 5; refinement++)
                {
                    float between = (last + distance) * .5f;
                    if (world.IsWater(start + direction * between, clearance)) last = between;
                    else distance = between;
                }
                return new(start, start + direction * last, windup, true);
            }
            last = distance;
        }
        return new(start, start + direction * Range, windup, false);
    }
}

public sealed partial class Voyage
{
    public const float BombOpening = 1.8f;
    public const float ChargeOpening = 2.25f;
    public const float GroundedOpening = 3.75f;

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
            AdvanceCrownclawCharge(boss, charge, dt);
            return true;
        }

        bool enraged = boss.Health < boss.MaxHealth * .5f;
        float reach = boss.ChargeNext ? CrownclawCharge.Range + boss.ContactRadius * .5f : 600;
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
                boss.Charge = CrownclawCharge.Aim(World, boss.Position, toward, boss.Radius, windup);
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

    void AdvanceCrownclawCharge(Enemy boss, CrownclawCharge charge, float dt)
    {
        if (boss.Telegraph > 0)
        {
            boss.Telegraph = Math.Max(0, boss.Telegraph - dt);
            if (boss.Telegraph > 0) return;
            boss.Dash = charge.Duration;
        }
        else
        {
            boss.Dash = Math.Max(0, boss.Dash - dt);
            boss.Position = charge.End - boss.Direction * (boss.Dash * CrownclawCharge.Speed);
        }
        if (boss.Dash > 0) return;

        boss.Charge = null;
        boss.Grounded = charge.HitsCoast;
        boss.Exposed = boss.Grounded ? GroundedOpening : ChargeOpening;
        if (boss.Grounded)
        {
            boss.AttackClock = GroundedOpening + .6f;
            Events.Add(new("crownclawGrounded", boss.Position, 155));
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
}
