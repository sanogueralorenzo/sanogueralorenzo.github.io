using System.Numerics;
namespace Further.Core;

public readonly record struct Cell(int X, int Z);
public sealed record Island(Cell Cell, Vector2 Center, float Radius, float Peak, int Biome, int Seed, string Name)
{
    public Vector2 Landing => Center + new Vector2(0, -Radius * .86f);
    public Vector2 Shrine => Center + new Vector2(Radius * .12f, Radius * .12f);
}
public sealed class World(int seed)
{
    public const int ChunkSize = 192;
    public int Seed { get; } = seed;
    public Cell Origin;
    public Cell CellAt(Vector2 p) => new(Origin.X + (int)MathF.Floor((p.X + ChunkSize / 2f) / ChunkSize), Origin.Z + (int)MathF.Floor((p.Y + ChunkSize / 2f) / ChunkSize));
    public static uint Hash(int x, int z, int seed)
    {
        uint h = unchecked((uint)(x * 374761393 + z * 668265263 + seed * 1442695041));
        h = (h ^ (h >> 13)) * 1274126177; return h ^ (h >> 16);
    }
    public Island IslandAt(Cell c)
    {
        int s = (int)(Hash(c.X, c.Z, Seed) & 0x7fffffff); var r = new Random(s);
        bool home = c == new Cell(0, 0);
        var center = new Vector2((c.X-Origin.X) * ChunkSize, (c.Z-Origin.Z) * ChunkSize) + (home ? Vector2.Zero : new Vector2(r.Next(-22, 23), r.Next(-22, 23)));
        string[] first = ["Copper", "Whisper", "Marigold", "Gull", "Juniper", "Lantern", "Coral", "Morrow"];
        string[] last = ["Cay", "Reach", "Hollow", "Heights", "Rest", "Cove"];
        return new(c, center, home ? 48 : r.Next(36, 63), home ? 11 : r.Next(9, 23), home ? 0 : r.Next(3), s, home ? "Marigold Cay" : $"{first[s % first.Length]} {last[(s / 9) % last.Length]}");
    }
    public float Height(Vector2 p) => Height(IslandAt(CellAt(p)), p);
    public static float Height(Island i, Vector2 p)
    {
        Vector2 q = p - i.Center; float angle = MathF.Atan2(q.Y, q.X);
        float rim = i.Radius * (1 + .105f * MathF.Sin(angle * 3 + i.Seed % 9) + .065f * MathF.Cos(angle * 5));
        float d = q.Length() / rim;
        if (d > 1.2f) return -5;
        float n = PrivateSources.Fractal(q.X + i.Seed % 400, q.Y, 4, 2.05f, .48f, 29);
        float h = (1 - d) * i.Peak * 1.45f + (n - .82f) * MathF.Max(0, 1 - d) * 9 - 1.7f;
        // A broad winding ascent keeps every summit reachable, with rocks framing it.
        float trailX = MathF.Sin(q.Y * .07f) * i.Radius * .19f;
        float path = Math.Clamp(1 - MathF.Abs(q.X - trailX) / 7, 0, 1);
        float ramp = (q.Y / i.Radius + .9f) * i.Peak * .52f;
        float shaped=h * (1 - path * .7f) + MathF.Min(h + 1, ramp) * path * .7f;
        float shrineDistance=Vector2.Distance(p,i.Shrine);
        float plateau=Math.Clamp((10-shrineDistance)/6,0,1);plateau=plateau*plateau*(3-2*plateau);
        return shaped*(1-plateau)+i.Peak*.65f*plateau;
    }
    public IEnumerable<Cell> Visible(Vector2 p, int radius = 2)
    {
        Cell c = CellAt(p);
        return from z in Enumerable.Range(c.Z - radius, radius * 2 + 1)
               from x in Enumerable.Range(c.X - radius, radius * 2 + 1)
               orderby Vector2.DistanceSquared(new((x-Origin.X) * ChunkSize, (z-Origin.Z) * ChunkSize), p)
               select new Cell(x, z);
    }
}
