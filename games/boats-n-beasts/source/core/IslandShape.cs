using System.Numerics;
namespace BoatsNBeasts.Core;

public enum IslandProfile { Compact, Long, Crescent, Lobed, Headland, Bean, Twin, Scalloped }

// One seeded outline shared by sand, shallows, the chart and collision.
public sealed class IslandShape
{
    public const int Sides = 192;
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
        if (rng.Unit() < .375f) Profile = (IslandProfile)(5 + rng.Index(3));
        float aspect = Profile switch
        {
            IslandProfile.Compact => rng.Range(.78f, 1),
            IslandProfile.Long => rng.Range(.28f, .48f),
            IslandProfile.Bean => rng.Range(.56f, .84f),
            _ => rng.Range(.72f, 1)
        };
        float rotation = rng.Range(0, MathF.Tau), phase = rng.Range(0, MathF.Tau);
        float lean = rng.Range(-.22f, .22f), relief = rng.Range(.80f, 1.20f);
        int scallops = rng.Index(2) + 4;
        // These bay guides round the back of the inlet instead of cutting a narrow V.
        Vector2[] bay = [new(.24f,0), new(.27f,.26f), new(.38f,.54f), new(.56f,.90f),
            new(.30f,1.05f), new(-.20f,1), new(-.72f,.75f), new(-1,.35f),
            new(-1.05f,0), new(-1,-.35f), new(-.72f,-.75f), new(-.20f,-1),
            new(.30f,-1.05f), new(.56f,-.90f), new(.38f,-.54f), new(.27f,-.26f)];
        var guides = new Vector2[16];
        float cr = MathF.Cos(rotation), sr = MathF.Sin(rotation);
        for (int i = 0; i < guides.Length; i++)
        {
            float t = i * MathF.Tau / guides.Length;
            float coast = Profile switch
            {
                IslandProfile.Compact => .91f + .08f * relief * MathF.Cos(3 * t + phase),
                IslandProfile.Long => .91f + .10f * MathF.Cos(t + phase),
                IslandProfile.Lobed => .78f + .21f * relief * MathF.Cos(3 * t + phase),
                IslandProfile.Headland => .64f + .35f * relief * Bump(t, 4),
                IslandProfile.Bean => .96f + .08f * MathF.Cos(t),
                IslandProfile.Twin => .69f + .32f * relief * MathF.Cos(2 * t) + .06f * MathF.Cos(t + phase),
                IslandProfile.Scalloped => .87f + .14f * relief * MathF.Cos(scallops * t + phase),
                _ => 1
            };
            var p = Profile == IslandProfile.Crescent ? bay[i] : new Vector2(MathF.Cos(t), MathF.Sin(t)) * coast;
            if (Profile == IslandProfile.Bean) p.Y += .65f * (1 - p.X * p.X);
            // Broad seeded variation and a small guide jitter change each family's proportions.
            p *= rng.Range(.94f, 1.06f) * (1 + .045f * MathF.Cos(2 * t + phase));
            p.Y *= aspect;
            p.X += lean * p.Y;
            guides[i] = new(p.X * cr - p.Y * sr, p.X * sr + p.Y * cr);
        }
        // Periodic cubic B-spline weights close the seam without overshooting the guides.
        var curve = new Vector2[256];
        for (int i = 0; i < curve.Length; i++)
        {
            float at = i * guides.Length / (float)curve.Length;
            int n = (int)at;
            float t = at - n, t2 = t * t, t3 = t2 * t, u = 1 - t;
            curve[i] = (guides[(n + 15) % 16] * (u * u * u) + guides[n] * (3 * t3 - 6 * t2 + 4)
                + guides[(n + 1) % 16] * (-3 * t3 + 3 * t2 + 3 * t + 1) + guides[(n + 2) % 16] * t3) / 6;
        }
        // Resample by polar angle for nested terrain layers and grounded prop placement.
        // The nearest positive intersection also keeps every radial layer simple.
        contour = new Vector2[Sides];
        float longest = 0;
        for (int i = 0; i < Sides; i++)
        {
            float a = i * MathF.Tau / Sides;
            var direction = new Vector2(MathF.Cos(a), MathF.Sin(a));
            float reach = float.MaxValue;
            for (int j = 0; j < curve.Length; j++)
            {
                var start = curve[j]; var edge = curve[(j + 1) % curve.Length] - start;
                float divisor = Cross(direction, edge);
                if (MathF.Abs(divisor) < .000001f) continue;
                float along = Cross(start, direction) / divisor, distance = Cross(start, edge) / divisor;
                if (along >= 0 && along <= 1 && distance > 0) reach = MathF.Min(reach, distance);
            }
            contour[i] = direction * reach;
            longest = MathF.Max(longest, reach);
        }
        // Radius remains the actual longest reach after smoothing.
        for (int i = 0; i < Sides; i++) contour[i] *= radius / longest;
        Shore = contour.Select(p => p * 1.04f).ToArray();
    }

    static float Bump(float angle, int power) => MathF.Pow((1 + MathF.Cos(angle)) * .5f, power);
    static float Cross(Vector2 a, Vector2 b) => a.X * b.Y - a.Y * b.X;

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
