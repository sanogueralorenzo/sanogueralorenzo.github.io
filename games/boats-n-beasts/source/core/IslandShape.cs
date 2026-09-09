using System.Numerics;
namespace BoatsNBeasts.Core;

public enum IslandProfile { Compact, Long, Crescent, Lobed, Headland }

// One seeded outline shared by sand, shallows, the chart and collision.
public sealed class IslandShape
{
    public const int Sides = 128;
    readonly float radius;
    readonly Vector2[] contour;
    public IslandProfile Profile { get; }
    public Vector2[] Shore { get; }
    public float Bounds => radius * 1.04f;

    public IslandShape(float radius, uint seed)
    {
        this.radius = radius;
        var rng = new SeedRandom(seed ^ 0x71a5bu);
        Profile = (IslandProfile)rng.Index(5);
        float aspect = Profile switch
        {
            IslandProfile.Compact => rng.Range(.80f, 1),
            IslandProfile.Long => rng.Range(.30f, .46f),
            IslandProfile.Crescent => rng.Range(.74f, .96f),
            IslandProfile.Lobed => rng.Range(.66f, .90f),
            _ => rng.Range(.70f, .92f)
        };
        float rotation = rng.Range(0, MathF.Tau), phase = rng.Range(0, MathF.Tau);
        float bayDepth = rng.Range(.76f, .84f);
        contour = new Vector2[Sides];
        float longest = 0;
        for (int i = 0; i < Sides; i++)
        {
            float a = i * MathF.Tau / Sides, t = a - rotation;
            float c = MathF.Cos(t), s = MathF.Sin(t);
            float ellipse = 1 / MathF.Sqrt(c * c + s * s / (aspect * aspect));
            float coast = Profile switch
            {
                IslandProfile.Compact => .92f + .065f * MathF.Cos(3 * t + phase),
                IslandProfile.Long => .93f + .07f * MathF.Cos(t + phase),
                IslandProfile.Crescent => 1 - bayDepth * MathF.Exp((c - 1) / .12f),
                IslandProfile.Lobed => .78f + .19f * MathF.Cos(3 * t + phase * .25f),
                _ => .59f + .41f * MathF.Exp((c - 1) / .12f) + .10f * MathF.Cos(2 * t + phase)
            };
            coast += .04f * MathF.Sin(5 * t + phase) + .025f * MathF.Sin(7 * t - phase);
            // Positive radial samples form a simple star-shaped polygon, including the bay.
            float reach = ellipse * MathF.Max(.12f, coast);
            contour[i] = new Vector2(MathF.Cos(a), MathF.Sin(a)) * reach;
            longest = MathF.Max(longest, reach);
        }
        // Radius describes the actual longest reach, rather than shrinking every family.
        for (int i = 0; i < Sides; i++) contour[i] *= radius / longest;
        Shore = contour.Select(p => p * 1.04f).ToArray();
    }

    public Vector2 Point(float angle)
    {
        float index = (angle / MathF.Tau % 1 + 1) % 1 * Sides;
        int i = (int)index;
        return Vector2.Lerp(contour[i], contour[(i + 1) % Sides], index - i);
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
