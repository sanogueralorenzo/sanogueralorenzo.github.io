using System.Numerics;
namespace BoatsNBeasts.Core;

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
public enum PlaceKind { Island, Rock, Harbor, Fishing }
public sealed record Place(string Id, PlaceKind Kind, Vector2 Position, float Radius, uint Style);
public sealed record OceanChunk(ChunkKey Key, Place[] Places);

// Adapted from Sno's coordinate-local RNG, edge clearance, bounded placement and streaming.
// Every chunk is pure seed+coordinate data. Mutable depletion lives separately, never in RNG.
public sealed class OceanWorld(uint seed)
{
    public const int ChunkSize = 1200;
    public uint Seed { get; } = seed;
    public Dictionary<ChunkKey, OceanChunk> Loaded { get; } = new();
    public Dictionary<string, int> Depletion { get; } = new();
    public HashSet<string> Discovered { get; } = new();
    private ChunkKey? lastCenter;
    private Place[] activePlaces = [];
    public static ChunkKey KeyAt(Vector2 p) => new((int)MathF.Floor((p.X + 600) / ChunkSize), (int)MathF.Floor((p.Y + 600) / ChunkSize));
    public static int TierAt(Vector2 p) => Math.Min(20, (int)(p.Length() / 1000));
    public OceanChunk Generate(ChunkKey key)
    {
        var rng = new SeedRandom(SeedRandom.Hash(Seed, key.X, key.Y, 17));
        var places = new List<Place>();
        var center = new Vector2(key.X * ChunkSize, key.Y * ChunkSize);
        void Add(PlaceKind kind, Vector2 p, float r) => places.Add(new($"{key.X}:{key.Y}:{places.Count}", kind, p, r, rng.Next()));
        if (key == new ChunkKey(0, 0))
        {
            Add(PlaceKind.Harbor, new(-310, -220), 140);
            Add(PlaceKind.Fishing, new(170, 180), 76);
            Add(PlaceKind.Island, new(410, 370), 80);
            Add(PlaceKind.Rock, new(390, -350), 40);
            return new(key, places.ToArray());
        }
        bool harbor = key.X % 3 == 0 && key.Y % 3 == 0;
        Add(harbor ? PlaceKind.Harbor : PlaceKind.Island, center + new Vector2(rng.Range(-180, 180), rng.Range(-180, 180)), harbor ? 140 : rng.Range(75, 132));
        int budget = 3 + rng.Index(3);
        for (int attempt = 0; attempt < 30 && places.Count < budget; attempt++)
        {
            // All solids stay inside the chunk, leaving continuous open lanes on every edge.
            Vector2 p = center + new Vector2(rng.Range(-370, 370), rng.Range(-370, 370));
            float r = rng.Range(28, 53);
            if (places.Any(a => Vector2.Distance(a.Position, p) < a.Radius + r + 120)) continue;
            Add(places.Count == 1 ? PlaceKind.Fishing : PlaceKind.Rock, p, places.Count == 1 ? 76 : r);
        }
        if (!places.Any(p => p.Kind == PlaceKind.Fishing)) Add(PlaceKind.Fishing, center + new Vector2(390, 390), 76);
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
    public IReadOnlyList<Place> Places => activePlaces;
    public int FishLeft(Place p) => Math.Max(0, 1 - Depletion.GetValueOrDefault(p.Id));
    public bool IsWater(Vector2 position, float clearance = 24) => !Places.Any(p => p.Kind != PlaceKind.Fishing && Vector2.Distance(position, p.Position) < p.Radius + clearance);
    public Vector2 Slide(Vector2 old, Vector2 target, float radius)
    {
        foreach (var p in Places)
        {
            if (p.Kind == PlaceKind.Fishing) continue;
            Vector2 d = target - p.Position; float min = radius + p.Radius;
            if (d.LengthSquared() < min * min) target = p.Position + Unit(d, Unit(old - p.Position, Vector2.UnitX)) * min;
        }
        return target;
    }
    public Vector2 Avoid(Vector2 position, Vector2 motion, float radius, int id)
    {
        // Choose a consistent tangent before touching a solid; chasing into an island
        // must not strand an enemy (especially the boss) on its far shoreline.
        float length = motion.Length(); if (length < .01f) return motion;
        var forward = motion / length;
        foreach (var p in Places)
        {
            if (p.Kind == PlaceKind.Fishing) continue;
            var to = p.Position - position; float distance = to.Length();
            if (distance > p.Radius + radius + 90 || Vector2.Dot(to, forward) < 0) continue;
            var normal = Unit(to); float cross = forward.X * normal.Y - forward.Y * normal.X;
            float side = Math.Abs(cross) < .08f ? (id % 2 == 0 ? 1 : -1) : -MathF.Sign(cross);
            return Unit(forward * .35f + new Vector2(-normal.Y, normal.X) * side) * length;
        }
        return motion;
    }
    public Place? HarborAt(Vector2 p) => Places.FirstOrDefault(a => a.Kind == PlaceKind.Harbor && Vector2.Distance(p, a.Position) < 285);
    public Place? FishAt(Vector2 p) => Places.FirstOrDefault(a => a.Kind == PlaceKind.Fishing && FishLeft(a) > 0 && Vector2.Distance(p, a.Position) < 130);
    public static Vector2 Unit(Vector2 v, Vector2 fallback = default) => v.LengthSquared() > .0001f ? Vector2.Normalize(v) : fallback;
}
