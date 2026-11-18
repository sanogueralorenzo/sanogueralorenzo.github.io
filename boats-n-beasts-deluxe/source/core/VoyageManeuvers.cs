using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed partial class Voyage
{
    public float ManeuverCooldown { get; private set; }
    public float ManeuverDuration => Spec.ManeuverSeconds;
    internal Vector2 Forward => new(MathF.Sin(Heading), -MathF.Cos(Heading));

    void UpdateManeuver(float dt, bool requested)
    {
        ManeuverCooldown = Math.Max(0, ManeuverCooldown - dt);
        if (!requested || ManeuverCooldown > 0) return;

        ManeuverCooldown = ManeuverDuration;
        if (Boat == BoatKind.Cutter)
        {
            var forward = Forward;
            var side = new Vector2(forward.Y, -forward.X);
            Events.Add(new("broadside", Position, 290));
            foreach (float direction in new[] { -1f, 1f })
            for (int i = -2; i <= 2; i++)
            {
                var aim = OceanWorld.Unit(side * direction + forward * (.23f * i));
                var muzzle = Position + aim * 53;
                Shots.Add(new()
                {
                    Kind = WeaponKind.Cannon, Position = muzzle, Previous = muzzle,
                    Velocity = aim * 770, Damage = 22 + Weapons[0] * 3,
                    Life = .82f, Radius = 11, Bounces = 1
                });
            }
            return;
        }

        if (Boat == BoatKind.Trawler)
        {
            const float radius = 278;
            Events.Add(new("bulwark", Position, radius));
            foreach (var shot in Shots)
                if (shot.Hostile && (Vector2.DistanceSquared(shot.Position, Position) < radius * radius ||
                    Vector2.DistanceSquared(shot.Target, Position) < radius * radius))
                    shot.Life = 0;
            foreach (var enemy in Enemies)
            {
                if (enemy.Health <= 0 || Vector2.Distance(enemy.Position, Position) > radius + enemy.Radius) continue;
                Hit(enemy, 26 + Weapons[4] * 4);
                enemy.Position = World.Slide(enemy.Position, enemy.Position +
                    OceanWorld.Unit(enemy.Position - Position) * 145, enemy.Radius);
            }
            Invulnerable = Math.Max(Invulnerable, .65f);
            return;
        }

        var start = Position;
        var heading = Forward;
        for (int step = 0; step < 10; step++)
        {
            var next = Position + heading * 29;
            if (!World.IsWater(next + heading * 35, 37)) break;
            Position = next;
        }
        Distance += Vector2.Distance(start, Position);
        Velocity += heading * Speed * .6f;
        Invulnerable = Math.Max(Invulnerable, .7f);
        Events.Add(new("blink", start, 110, Position));
        foreach (var enemy in Enemies)
            if (enemy.Health > 0 && SegmentDistance(enemy.Position, start, Position) < 86 + enemy.Radius)
                Hit(enemy, 35 + Weapons[5] * 5);
    }
}
