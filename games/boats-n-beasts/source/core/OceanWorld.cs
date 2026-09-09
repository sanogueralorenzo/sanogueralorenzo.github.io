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
public enum PlaceKind { Island, Rock, Harbor, Fishing, Treasure, Current, Wreck }
public sealed record Place(string Id, PlaceKind Kind, Vector2 Position, float Radius, uint Style)
{
    IslandShape? shape;
    public IslandShape? Shape => Kind == PlaceKind.Island ? shape ??= new(Radius, Style) : null;
}
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
    // One broadly scattered candidate per chunk, thinned against neighboring candidates.
    // Acceptance depends only on seed/coordinates, never on chunk loading order.
    Place? LandmarkCandidate(ChunkKey key)
    {
        if (StartingArea.Contains(key)) return null;
        // Mix axes separately so opposite signed coordinates do not repeat patterns.
        uint columnSeed = SeedRandom.Hash(Seed, key.X, 0, 317);
        var rng = new SeedRandom(SeedRandom.Hash(columnSeed, 0, key.Y, 719));
        if (rng.Unit() >= .42f) return null;
        var position = new Vector2(key.X * ChunkSize, key.Y * ChunkSize) +
            new Vector2(rng.Range(-500, 500), rng.Range(-500, 500));
        bool harbor = rng.Unit() < .3f;
        // Separated size bands read as islets, islands and substantial landmasses.
        float size = rng.Unit();
        float radius = harbor ? 140 : size < .35f ? rng.Range(80, 115)
            : size < .78f ? rng.Range(165, 235) : rng.Range(290, 360);
        return new($"{key.X}:{key.Y}:land", harbor ? PlaceKind.Harbor : PlaceKind.Island,
            position, radius, rng.Next());
    }
    IEnumerable<Place> Landmarks(ChunkKey key)
    {
        var land = LandmarkCandidate(key);
        if (land == null) yield break;
        for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++)
        {
            if (x == 0 && y == 0) continue;
            var other = LandmarkCandidate(new(key.X + x, key.Y + y));
            if (other == null) continue;
            float spacing = MathF.Max(900, (land.Radius + other.Radius) * 1.04f + 320);
            if (Vector2.DistanceSquared(land.Position, other.Position) >= spacing * spacing) continue;
            // Coordinate tie-break keeps even equal hash priorities deterministic.
            if (other.Style < land.Style || (other.Style == land.Style && (y < 0 || (y == 0 && x < 0)))) yield break;
        }
        yield return land;
        if (land.Kind == PlaceKind.Harbor) yield break;
        var rng = new SeedRandom(land.Style);
        float angle = rng.Range(0, MathF.Tau);
        for (int rock = 0; rock < 2; rock++)
        {
            float a = angle + rock * .42f;
            yield return new($"{key.X}:{key.Y}:shore:{rock}", PlaceKind.Rock,
                land.Position + land.Shape!.Point(a) * 1.04f + new Vector2(MathF.Cos(a), MathF.Sin(a)) * 85,
                rng.Range(24, 35), rng.Next());
        }
    }
    public OceanChunk Generate(ChunkKey key)
    {
        if (StartingArea.Contains(key)) return StartingArea.Generate(key);
        var rng = new SeedRandom(SeedRandom.Hash(Seed, key.X, key.Y, 17));
        var places = Landmarks(key).ToList();
        var center = new Vector2(key.X * ChunkSize, key.Y * ChunkSize);
        // Wide offsets can carry a shore across a chunk edge. Keep encounters clear
        // of neighboring land too, without requiring those chunks to be loaded.
        var nearbySolids = new List<Place>();
        for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++)
        {
            var neighbor = new ChunkKey(key.X + x, key.Y + y);
            nearbySolids.AddRange(StartingArea.Contains(neighbor)
                ? StartingArea.Generate(neighbor).Places.Where(IsSolid) : Landmarks(neighbor));
        }
        for (int attempt = 0; attempt < 48; attempt++)
        {
            Vector2 p = center + new Vector2(rng.Range(-400, 400), rng.Range(-400, 400));
            if (nearbySolids.Any(a => Vector2.Distance(a.Position, p) < a.Radius + 165)) continue;
            places.Add(new($"{key.X}:{key.Y}:fishing", PlaceKind.Fishing, p, 76, rng.Next()));
            break;
        }
        AddEncounters(key, places, nearbySolids);
        return new(key, places.ToArray());
    }
    void AddEncounters(ChunkKey key, List<Place> places, IReadOnlyList<Place> nearbySolids)
    {
        var rng = new SeedRandom(SeedRandom.Hash(Seed,key.X,key.Y,91));
        var center = new Vector2(key.X*ChunkSize,key.Y*ChunkSize);
        void Add(PlaceKind kind, Vector2 at, float radius, uint? style = null) => places.Add(new($"{key.X}:{key.Y}:encounter:{places.Count}",kind,at,radius,style ?? rng.Next()));
        bool TryPosition(float clearance, out Vector2 position)
        {
            for(int i=0;i<16;i++)
            {
                position=center+new Vector2(rng.Range(-310,310),rng.Range(-310,310));
                var candidate=position;
                if(places.All(p=>Vector2.Distance(p.Position,candidate)>=p.Radius+clearance) &&
                    nearbySolids.All(p=>Vector2.Distance(p.Position,candidate)>=p.Radius+clearance)) return true;
            }
            position=default; return false;
        }
        if(rng.Unit()<.55f && TryPosition(90,out var treasure)) Add(PlaceKind.Treasure,treasure,22);
        if(rng.Unit()<.35f && TryPosition(150,out var current)) Add(PlaceKind.Current,current,245);
        if(rng.Unit()<.24f && TryPosition(175,out var wreck))
        {
            Add(PlaceKind.Wreck,wreck,65);
            Add(PlaceKind.Rock,wreck+new Vector2(-110,-55),32);
            Add(PlaceKind.Rock,wreck+new Vector2(110,55),34);
        }
    }
    public static bool IsSolid(Place place) => place.Kind is PlaceKind.Island or PlaceKind.Rock or PlaceKind.Harbor;
    public static Vector2 FlowDirection(Place current)
    {
        float angle = current.Style % 16 * MathF.Tau / 16;
        return new(MathF.Cos(angle),MathF.Sin(angle));
    }
    public Vector2 FlowAt(Vector2 position)
    {
        Vector2 flow=default;
        foreach(var current in Places)
        {
            if(current.Kind!=PlaceKind.Current) continue;
            var direction=FlowDirection(current); var offset=position-current.Position;
            float along=Vector2.Dot(offset,direction)/current.Radius;
            float across=Vector2.Dot(offset,new(-direction.Y,direction.X))/(current.Radius*.3f);
            float weight=1-along*along-across*across;
            if(weight>0) flow+=direction*125*Math.Min(1,weight*2);
        }
        return flow.Length()>150?Unit(flow)*150:flow;
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
    public static bool Overlap(Place place, Vector2 position, float clearance, out Vector2 normal, out float depth)
    {
        var offset = position - place.Position;
        if (place.Shape is { } shape) return shape.Overlap(offset, clearance, out normal, out depth);
        float distance = offset.Length();
        normal = Unit(offset, Vector2.UnitX); depth = place.Radius + clearance - distance;
        return depth > 0;
    }
    public bool IsWater(Vector2 position, float clearance = 24) => !Places.Any(p => IsSolid(p) && Overlap(p, position, clearance, out _, out _));
    public Vector2 Slide(Vector2 old, Vector2 target, float radius)
    {
        foreach (var p in Places)
        {
            if (!IsSolid(p)) continue;
            if (Overlap(p, target, radius, out var normal, out float depth)) target += normal * depth;
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
            if (!IsSolid(p)) continue;
            var to = p.Position - position; float distance = to.Length();
            if (distance > p.Radius * 1.04f + radius + 90 || Vector2.Dot(to, forward) < 0) continue;
            if (p.Shape != null && !Overlap(p, position + forward * 90, radius, out _, out _)) continue;
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
