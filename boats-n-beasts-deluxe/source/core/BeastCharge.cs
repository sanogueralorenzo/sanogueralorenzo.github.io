using System.Numerics;
namespace BoatsNBeasts.Core;

public readonly record struct BeastCharge(Vector2 Start, Vector2 End, float Windup, float Speed, bool HitsCoast)
{
    public float Duration => Vector2.Distance(Start, End) / Speed;

    public static BeastCharge Aim(OceanWorld world, Vector2 start, Vector2 direction, float clearance,
        float windup, float range, float speed)
    {
        const float step = 8;
        float last = 0;
        for (int i = 1; i <= (int)MathF.Ceiling(range / step); i++)
        {
            float distance = Math.Min(i * step, range);
            var point = start + direction * distance;
            if (!world.IsWater(point, clearance))
            {
                for (int refinement = 0; refinement < 5; refinement++)
                {
                    float between = (last + distance) * .5f;
                    if (world.IsWater(start + direction * between, clearance)) last = between;
                    else distance = between;
                }
                return new(start, start + direction * last, windup, speed, true);
            }
            last = distance;
        }
        return new(start, start + direction * range, windup, speed, false);
    }

    public bool Advance(Enemy enemy, float dt)
    {
        if (enemy.Telegraph > 0)
        {
            enemy.Telegraph = Math.Max(0, enemy.Telegraph - dt);
            if (enemy.Telegraph > 0) return false;
            enemy.Dash = Duration;
        }
        else
        {
            enemy.Dash = Math.Max(0, enemy.Dash - dt);
            enemy.Position = End - enemy.Direction * (enemy.Dash * Speed);
        }
        if (enemy.Dash > 0) return false;
        enemy.Charge = null;
        return true;
    }
}
