using System.Numerics;

namespace BoatsNBeasts.Core;

public static class QuayPaths
{
    public static readonly Vector2 Summit = new(0, -17.1f);
    public static readonly Vector2 Dock = new(-2.4f, 4.05f);
    public static readonly Vector2[] Bells = [new(-4.65f, -8.1f), new(4.65f, -8.1f)];
    public static readonly Vector2[] Anchors = [Summit + new Vector2(-2.65f, .25f), Summit + new Vector2(2.65f, .25f)];
    public static readonly Vector2 Belfry = Summit + new Vector2(0, -1.8f);
    public static readonly (Vector2 From, Vector2 To)[] Bridges = [
        (new(-1.72f,-2.55f),new(-4.28f,-6.70f)), (new(1.72f,-2.55f),new(4.28f,-6.70f)),
        (new(-2.8f,-8.1f),new(2.8f,-8.1f)),
        (new(-4.28f,-9.8f),new(-1.72f,-14.4f)), (new(4.28f,-9.8f),new(1.72f,-14.4f))];
    static readonly Vector2 Court = new(4.9f, 3.55f), Station = new(2.45f, 2.2f);

    public static Vector2 Walkable(Vector2 point)
    {
        var best = Vector2.Clamp(point, new(Dock.X - .54f, 2.4f), new(Dock.X + .54f, 4.35f));
        void Consider(Vector2 p)
        {
            if (Vector2.DistanceSquared(point, p) < Vector2.DistanceSquared(point, best)) best = p;
        }
        void Island(Vector2 center, Vector2 radii)
        {
            var v = (point - center) / radii;
            Consider(v.LengthSquared() <= 1 ? point : center + Vector2.Normalize(v) * radii);
        }
        Island(Vector2.Zero, Court); Island(Summit, Court);
        foreach (var bell in Bells) Island(bell, Station);
        foreach (var (from, to) in Bridges)
        {
            var d = to - from;
            var foot = from + d * Math.Clamp(Vector2.Dot(point - from, d) / d.LengthSquared(), 0, 1);
            var offset = point - foot;
            Consider(offset.LengthSquared() <= .59f * .59f ? point : foot + Vector2.Normalize(offset) * .59f);
        }
        return best;
    }
}
