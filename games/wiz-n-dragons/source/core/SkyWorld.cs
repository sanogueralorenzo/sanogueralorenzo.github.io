using System.Numerics;
namespace WizNDragons.Core;

public struct SeedRandom
{
    public uint State;
    public SeedRandom(uint seed) => State = seed == 0 ? 1 : seed;
    public uint Next() { uint x = State; x ^= x << 13; x ^= x >> 17; x ^= x << 5; return State = x; }
    public float Unit() => (Next() >> 8) / 16777216f;
    public float Range(float min, float max) => min + (max - min) * Unit();
    public int Index(int count) => (int)(Next() % count);
    public static uint Hash(uint seed, int x, int y, uint salt = 0)
    {
        unchecked { uint h = seed ^ (uint)x * 0x9e3779b9 ^ (uint)y * 0x85ebca6b ^ salt;
        h ^= h >> 16; h *= 0x7feb352d; h ^= h >> 15; h *= 0x846ca68b; return h ^ (h >> 16); }
    }
}
public readonly record struct ChunkKey(int X, int Y);
public enum PlaceKind { Crystal, Current, Potion }
public sealed record Place(string Id, PlaceKind Kind, Vector2 Position, float Radius, uint Style, float Heading = 0);
public sealed record SkyChunk(ChunkKey Key, Place[] Places);

// Infinite open flight space. Chunks own encounters only; clouds never block movement.
public sealed class SkyWorld(uint seed)
{
    public const int ChunkSize = 1200;
    public uint Seed { get; } = seed;
    public Dictionary<ChunkKey, SkyChunk> Loaded { get; } = new();
    public Dictionary<string, int> Depletion { get; } = new();
    public HashSet<string> Discovered { get; } = new();
    ChunkKey? lastCenter;
    Place[] activePlaces = [];
    public IReadOnlyList<Place> Places => activePlaces;
    public static ChunkKey KeyAt(Vector2 p) => new((int)MathF.Floor((p.X + 600) / ChunkSize), (int)MathF.Floor((p.Y + 600) / ChunkSize));
    public SkyChunk Generate(ChunkKey key)
    {
        var rng = new SeedRandom(SeedRandom.Hash(Seed, key.X, key.Y, 17));
        var places = new List<Place>();
        void Add(PlaceKind kind, float radius)
        {
            var p = new Vector2(key.X * ChunkSize + rng.Range(-400, 400), key.Y * ChunkSize + rng.Range(-400, 400));
            if (places.Any(other => Vector2.Distance(other.Position, p) < other.Radius + radius + 100)) return;
            places.Add(new($"{key.X}:{key.Y}:{kind}", kind, p, radius, rng.Next()));
        }
        if (key != new ChunkKey(0, 0))
        {
            if (rng.Unit() < .30f) Add(PlaceKind.Potion, 24);
            if (rng.Unit() < .20f) Add(PlaceKind.Crystal, 25);
            if (rng.Unit() < .35f) Add(PlaceKind.Current, 245);
        }
        return new(key, places.ToArray());
    }
    public void Stream(Vector2 position)
    {
        var center = KeyAt(position);
        if (center == lastCenter) return;
        lastCenter = center;
        foreach (var key in Loaded.Keys.ToArray())
            if (Math.Abs(key.X - center.X) > 2 || Math.Abs(key.Y - center.Y) > 2) Loaded.Remove(key);
        for (int y = -2; y <= 2; y++) for (int x = -2; x <= 2; x++)
        {
            var key = new ChunkKey(center.X + x, center.Y + y);
            if (!Loaded.ContainsKey(key)) Loaded.Add(key, Generate(key));
        }
        activePlaces = Loaded.Values.SelectMany(c => c.Places).ToArray();
    }
    public static Vector2 FlowDirection(Place current)
    {
        float angle = current.Style % 16 * MathF.Tau / 16;
        return new(MathF.Cos(angle), MathF.Sin(angle));
    }
    public Vector2 FlowAt(Vector2 position)
    {
        Vector2 flow = default;
        foreach (var current in Places.Where(p => p.Kind == PlaceKind.Current))
        {
            var direction = FlowDirection(current); var offset = position - current.Position;
            float along = Vector2.Dot(offset, direction) / current.Radius;
            float across = Vector2.Dot(offset, new(-direction.Y, direction.X)) / (current.Radius * .3f);
            float weight = 1 - along * along - across * across;
            if (weight > 0) flow += direction * 125 * Math.Min(1, weight * 2);
        }
        return flow.Length() > 150 ? Unit(flow) * 150 : flow;
    }
    public static Vector2 Unit(Vector2 v, Vector2 fallback = default) => v.LengthSquared() > .0001f ? Vector2.Normalize(v) : fallback;
}
