using System.Numerics;

namespace CozySora.Water;

/// <summary>Continuous square rings around a dense grid. Unequal ring counts share stitched edges.</summary>
public sealed record WaterMesh(Vector3[] Vertices, int[] Indices)
{
    public static WaterMesh Ocean()
    {
        var vertices = new List<Vector3>(); var indices = new List<int>();
        const int divisions = 192; const float radius = 108;
        for (int z = 0; z <= divisions; z++) for (int x = 0; x <= divisions; x++)
            vertices.Add(new(-radius + 2 * radius * x / divisions, 0, -radius + 2 * radius * z / divisions));
        for (int z = 0; z < divisions; z++) for (int x = 0; x < divisions; x++)
        {
            int a = z * (divisions + 1) + x, b = a + 1, c = a + divisions + 1, d = c + 1;
            indices.AddRange((x + z) % 2 == 0 ? [a, c, b, b, c, d] : [a, c, d, a, d, b]);
        }
        List<int> previous = [];
        for (int i = 0; i < divisions; i++) previous.Add(i);
        for (int i = 0; i < divisions; i++) previous.Add(i * (divisions + 1) + divisions);
        for (int i = 0; i < divisions; i++) previous.Add(divisions * (divisions + 1) + divisions - i);
        for (int i = 0; i < divisions; i++) previous.Add((divisions - i) * (divisions + 1));
        (float Radius, int Segments, int Rings, float Power)[] bands = [(210, 192, 24, 1.23f), (520, 96, 24, 1.2f), (1150, 48, 20, 1.18f), (2920, 24, 18, 1.15f)];
        float inner = radius;
        foreach (var band in bands)
        {
            for (int ring = 1; ring <= band.Rings; ring++)
            {
                float r = inner + (band.Radius - inner) * MathF.Pow((float)ring / band.Rings, band.Power);
                List<int> next = [];
                for (int side = 0; side < 4; side++) for (int step = 0; step < band.Segments; step++)
                {
                    float along = -r + 2 * r * step / band.Segments;
                    next.Add(vertices.Count);
                    vertices.Add(side switch { 0 => new(along, 0, -r), 1 => new(r, 0, along), 2 => new(-along, 0, r), _ => new(-r, 0, -along) });
                }
                int a = 0, b = 0;
                while (a < previous.Count || b < next.Count)
                {
                    int i = previous[a % previous.Count], j = next[b % next.Count];
                    long advanceInner = (long)(a + 1) * next.Count, advanceOuter = (long)(b + 1) * previous.Count;
                    if (advanceInner < advanceOuter) { indices.AddRange([i, previous[(++a) % previous.Count], j]); }
                    else if (advanceOuter < advanceInner) { indices.AddRange([i, next[(++b) % next.Count], j]); }
                    else
                    {
                        bool alternate = (a + b + ring - 1) % 2 != 0;
                        int p = previous[(++a) % previous.Count], q = next[(++b) % next.Count];
                        indices.AddRange(alternate ? [i, p, q, i, q, j] : [i, p, j, p, q, j]);
                    }
                }
                previous = next;
            }
            inner = band.Radius;
        }
        return new(vertices.ToArray(), indices.ToArray());
    }
}
