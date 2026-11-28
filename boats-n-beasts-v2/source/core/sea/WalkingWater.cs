using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed partial class SeaWeather
{
    bool WalkingWater(Voyage ship, float dt, float period)
    {
        var climate = country.Climate;
        if (climate < SeaClimate.Salt) return false;
        Windup = cycle / period;
        Marked = true;
        Center = source;
        switch (climate)
        {
            case SeaClimate.Salt:
                Radius = 105 + 95 * Windup;
                if (Math.Abs(Vector2.Distance(ship.Position, Center) - Radius) < 32 && !ship.IsBoosting)
                    ship.Velocity *= MathF.Exp(-3 * dt);
                if (cycle >= period && Vector2.DistanceSquared(ship.Position, Center) < 90 * 90) ship.Boost = Math.Min(100, ship.Boost + 22);
                break;
            case SeaClimate.Bottle:
                Center = source + new Vector2(MathF.Cos(Clock * .5f), MathF.Sin(Clock * .7f)) * 96;
                Radius = 108;
                if (Vector2.DistanceSquared(ship.Position, Center) < Radius * Radius)
                {
                    if (ship.Events.Any(e => e.Kind == "shot") && exposure <= 0)
                    {
                        ship.Events.Add(new("bossExplosion", Center, 105));
                        ship.HullHit(10); exposure = 3;
                    }
                    else if (exposure <= 0) ship.Boost = Math.Min(100, ship.Boost + dt * 18);
                }
                exposure = Math.Max(0, exposure - dt);
                break;
            case SeaClimate.Wax:
                Radius = 170;
                Center = source + new Vector2(MathF.Sin(Clock * .44f) * 132, MathF.Cos(Clock * .44f) * 60);
                if (Vector2.DistanceSquared(ship.Position, Center) < Radius * Radius)
                {
                    var wind = OceanWorld.Unit(new(MathF.Cos(Clock * .44f), -.30f));
                    ship.Position = ship.World.Slide(ship.Position, ship.Position + wind * (HeadingAlong(ship, wind) > .25f ? 125 : 61) * dt, 33);
                    if (HeadingAlong(ship, wind) > .63f) ship.Boost = Math.Min(100, ship.Boost + 11 * dt);
                }
                break;
            case SeaClimate.Sleep:
                Radius = 175;
                if (Vector2.DistanceSquared(ship.Position, Center) < Radius * Radius)
                {
                    bool loud = ship.IsBoosting || ship.Events.Any(e => e.Kind == "shot");
                    exposure = Math.Clamp(exposure + dt * (ship.IsBoosting ? 1.5f : -.18f) + (loud && !ship.IsBoosting ? .53f : 0), 0, 2.25f);
                    Windup = exposure / 2.25f;
                    if (exposure >= 2.25f)
                    {
                        ship.Events.Add(new("bossExplosion", Center, 180));
                        ship.HullHit(12); ship.Velocity += OceanWorld.Unit(ship.Position - Center) * 160;
                        exposure = 0;
                    }
                }
                break;
            case SeaClimate.Tin:
                Radius = 212;
                float distance = Vector2.Distance(ship.Position, Center);
                if (distance < Radius && distance > 48 && !ship.IsBoosting)
                {
                    var pull = OceanWorld.Unit(Center - ship.Position) * ((1 - distance / Radius) * 128);
                    ship.Position = ship.World.Slide(ship.Position, ship.Position + pull * dt, 33);
                    foreach (var shot in ship.Shots.Where(s => !s.Hostile && s.Kind == WeaponKind.Cannon && Vector2.DistanceSquared(s.Position, Center) < Radius * Radius))
                        shot.Velocity += OceanWorld.Unit(Center - shot.Position) * 235 * dt;
                }
                break;
            case SeaClimate.Drum:
                Radius = 280;
                float ring = Radius * (1 - Windup);
                if (Math.Abs(Vector2.Distance(ship.Position, Center) - ring) < 17)
                {
                    if (ship.IsBoosting) ship.Boost = Math.Min(100, ship.Boost + 35 * dt);
                    else ship.HullHit(11);
                }
                break;
            case SeaClimate.Pitch:
                Radius = 145;
                Center = source + new Vector2(MathF.Cos(Clock * .31f) * 76, 0);
                if (Vector2.DistanceSquared(ship.Position, Center) < Radius * Radius)
                {
                    if (!ship.IsBoosting) ship.Velocity *= MathF.Exp(-3.3f * dt);
                    foreach (var foe in ship.Enemies)
                        if (Vector2.DistanceSquared(foe.Position, Center) < Radius * Radius) foe.Stunned = Math.Max(foe.Stunned, .10f);
                }
                break;
            case SeaClimate.Calving:
                var axis = new Vector2(MathF.Cos(Clock * .32f), MathF.Sin(Clock * .32f));
                Center = source + axis * 156; Radius = 131;
                if (Vector2.DistanceSquared(ship.Position, Center) < Radius * Radius)
                {
                    var swim = new Vector2(-axis.Y, axis.X);
                    ship.Position = ship.World.Slide(ship.Position, ship.Position + swim * 114 * dt, 34);
                    if (HeadingAlong(ship, swim) > .5f) ship.Boost = Math.Min(100, ship.Boost + 23 * dt);
                }
                break;
        }
        return true;
    }

    static float HeadingAlong(Voyage ship, Vector2 dir) => Vector2.Dot(OceanWorld.Unit(ship.Velocity), dir);
}
