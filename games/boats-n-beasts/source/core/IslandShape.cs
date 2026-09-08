using System.Numerics;
namespace BoatsNBeasts.Core;

// One smooth seeded outline shared by sand, shallows, the chart and collision.
public sealed class IslandShape
{
    public const int Sides = 96;
    readonly float radius, aspect, rotation, phase, bend;
    public Vector2[] Shore { get; }
    public float Bounds => radius * 1.04f;

    public IslandShape(float radius, uint seed)
    {
        this.radius = radius;
        var rng = new SeedRandom(seed ^ 0x71a5bu);
        aspect = rng.Range(.48f, .88f);
        rotation = rng.Range(0, MathF.Tau);
        phase = rng.Range(0, MathF.Tau);
        bend = rng.Range(.10f, .23f);
        Shore = Enumerable.Range(0, Sides).Select(i => Point(i * MathF.Tau / Sides) * 1.04f).ToArray();
    }

    public Vector2 Point(float angle)
    {
        float local = angle - rotation, c = MathF.Cos(local), s = MathF.Sin(local);
        float ellipse = 1 / MathF.Sqrt(c * c + s * s / (aspect * aspect));
        float coast = (.79f + bend * MathF.Cos(local + phase) + .13f * MathF.Cos(2 * local - phase)
            + .05f * MathF.Sin(3 * local + phase)) / 1.20f;
        return new Vector2(MathF.Cos(angle), MathF.Sin(angle)) * (radius * ellipse * coast);
    }

    public Vector2 PlaceOnLand(Vector2 offset)
    {
        float distance = offset.Length();
        return distance < .001f ? Vector2.Zero : Point(MathF.Atan2(offset.Y, offset.X)) * (distance / radius);
    }

    // Closest polygon edge gives boats and enemies clearance even inside a curved inlet.
    public bool Overlap(Vector2 local, float clearance, out Vector2 normal, out float depth)
    {
        normal = default; depth = 0;
        if (local.LengthSquared() > MathF.Pow(Bounds + clearance, 2)) return false;
        float best = float.MaxValue;
        Vector2 closest = default, edgeNormal = default;
        bool inside = false;
        for (int i = 0; i < Shore.Length; i++)
        {
            var a = Shore[i]; var b = Shore[(i + 1) % Shore.Length]; var edge = b - a;
            var point = a + edge * Math.Clamp(Vector2.Dot(local - a, edge) / edge.LengthSquared(), 0, 1);
            float distance = Vector2.DistanceSquared(local, point);
            if (distance < best) { best = distance; closest = point; edgeNormal = Vector2.Normalize(new Vector2(edge.Y, -edge.X)); }
            if ((a.Y > local.Y) != (b.Y > local.Y) && local.X < (b.X - a.X) * (local.Y - a.Y) / (b.Y - a.Y) + a.X) inside = !inside;
        }
        float gap = MathF.Sqrt(best);
        if (!inside && gap >= clearance) return false;
        normal = gap > .001f ? (inside ? closest - local : local - closest) / gap : edgeNormal;
        depth = inside ? clearance + gap : clearance - gap;
        return true;
    }
}
