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
public enum PlaceKind { Island, Rock, Harbor, Treasure, Current, Barrel }
public sealed record Place(string Id, PlaceKind Kind, Vector2 Position, float Radius, uint Style, float Heading = 0)
{
    IslandShape? shape;
    public IslandShape? Shape => Kind == PlaceKind.Island ? shape ??= new(Radius, Style) : null;
}
public sealed record OceanChunk(ChunkKey Key, Place[] Places);

// Chunks depend only on seed and coordinates; depletion is stored separately.
public sealed class OceanWorld(uint seed)
{
    public const int ChunkSize = 1200;
    public const float MaxRegularIslandRadius = 720;
    public const float PrisonIslandRadius = 1200;
    public const float MaxIslandRadius = PrisonIslandRadius;
    public static bool IsPrisonIsland(float radius, uint style) => radius >= PrisonIslandRadius && IsPrisonStyle(style);
    private static bool IsPrisonStyle(uint style) => new SeedRandom(style ^ 0xa43fu).Index(8) == 0;
    public const float IslandTreasureChance = .15f;
    public const float BarrelChance = .20f;
    public const float BarrelSpacing = 900;
    public uint Seed { get; } = seed;
    public Dictionary<ChunkKey, OceanChunk> Loaded { get; } = new();
    public Dictionary<string, int> Depletion { get; } = new();
    public HashSet<string> Discovered { get; } = new();
    private ChunkKey? lastCenter;
    private Place[] activePlaces = [];
    public static ChunkKey KeyAt(Vector2 p) => new((int)MathF.Floor((p.X + 600) / ChunkSize), (int)MathF.Floor((p.Y + 600) / ChunkSize));
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
        float size = rng.Unit();
        float radius = size < .35f ? rng.Range(80, 115)
            : size < .70f ? rng.Range(165, 235) : size < .85f ? rng.Range(290, 360)
            : rng.Range(520, MaxRegularIslandRadius);
        uint style = rng.Next();
        // Prison destinations reserve their real coastline before spacing or collision.
        if (radius >= 250 && IsPrisonStyle(style)) radius = PrisonIslandRadius;
        // Giant islands can reach toward home from outside its reserved chunks.
        if (StartingArea.Places.Any(p => IsSolid(p) && Vector2.Distance(position, p.Position) <
            (radius + p.Radius) * 1.04f + 320)) return null;
        return new($"{key.X}:{key.Y}:land", PlaceKind.Island,
            position, radius, style);
    }
    IEnumerable<Place> Landmarks(ChunkKey key)
    {
        var land = LandmarkCandidate(key);
        if (land == null) yield break;
        // Maximum spacing is 2,816 units including prison islands. Four chunks
        // apart are at least 3,800 apart; three neighbors in each direction suffice.
        for (int y = -3; y <= 3; y++) for (int x = -3; x <= 3; x++)
        {
            if (x == 0 && y == 0) continue;
            var other = LandmarkCandidate(new(key.X + x, key.Y + y));
            if (other == null) continue;
            float spacing = MathF.Max(900, (land.Radius + other.Radius) * 1.04f + 320);
            if (Vector2.DistanceSquared(land.Position, other.Position) >= spacing * spacing) continue;
            // Reserve rare prison destinations before ordinary islands; otherwise
            // their larger exclusion radius makes them almost always lose thinning.
            bool prison = IsPrisonIsland(land.Radius, land.Style);
            bool otherPrison = IsPrisonIsland(other.Radius, other.Style);
            if (prison != otherPrison)
            {
                if (otherPrison) yield break;
            }
            // Coordinate tie-break keeps equal priorities deterministic.
            else if (other.Style < land.Style || (other.Style == land.Style && (y < 0 || (y == 0 && x < 0)))) yield break;
        }
        yield return land;
        foreach (var rock in ShoreRocks(land)) yield return rock;
    }
    static IEnumerable<Place> ShoreRocks(Place land)
    {
        var rng = new SeedRandom(land.Style);
        float angle = rng.Range(0, MathF.Tau);
        for (int rock = 0; rock < 2; rock++)
        {
            float a = angle + rock * .42f;
            yield return new(land.Id.Replace(":land", $":shore:{rock}"), PlaceKind.Rock,
                land.Position + land.Shape!.Point(a) * 1.04f + new Vector2(MathF.Cos(a), MathF.Sin(a)) * 85,
                rng.Range(24, 35), rng.Next());
        }
    }
    // The same shore anchor reserves a clear patch in the procedural island art.
    public static Place? IslandTreasure(Place island)
    {
        if (island.Kind != PlaceKind.Island || island.Id.StartsWith("home:")) return null;
        var rng = new SeedRandom(island.Style ^ 0x4ba173u);
        if (rng.Unit() >= IslandTreasureChance) return null;
        var shape = island.Shape!;
        var rocks = ShoreRocks(island).ToArray();
        int start = rng.Index(IslandShape.Sides);
        for (int attempt = 0; attempt < 32; attempt++)
        {
            int side = (start + attempt * 6) % IslandShape.Sides;
            var a = shape.Shore[side]; var b = shape.Shore[(side + 1) % IslandShape.Sides];
            var normal = Unit(new Vector2(b.Y - a.Y, a.X - b.X));
            var coast = (a + b) * .5f;
            var chest = coast - normal * 22;
            var approach = coast + normal * 100;
            // Keep the chest on land and an entire boat clear of concave shores/rocks.
            if (!shape.Overlap(chest, 0, out _, out float depth) || depth < 18 ||
                shape.Overlap(approach, 75, out _, out _) ||
                shape.Overlap(coast + normal * 200, 75, out _, out _) ||
                rocks.Any(p => Vector2.Distance(p.Position, island.Position + approach) < p.Radius + 85 ||
                    Vector2.Distance(p.Position, island.Position + chest) < p.Radius + 45)) continue;
            return new(island.Id + ":treasure", PlaceKind.Treasure, island.Position + chest, 22,
                rng.Next(), MathF.Atan2(normal.X, normal.Y));
        }
        return null;
    }
    Place? BarrelCandidate(ChunkKey key)
    {
        if (StartingArea.Contains(key)) return null;
        uint column = SeedRandom.Hash(Seed, key.X, 0, 521);
        var rng = new SeedRandom(SeedRandom.Hash(column, 0, key.Y, 907));
        if (rng.Unit() >= BarrelChance) return null;
        return new($"{key.X}:{key.Y}:barrel", PlaceKind.Barrel,
            new Vector2(key.X * ChunkSize + rng.Range(-450, 450), key.Y * ChunkSize + rng.Range(-450, 450)),
            23, rng.Next());
    }
    void AddBarrel(ChunkKey key, List<Place> places, IReadOnlyList<Place> solids)
    {
        var barrel = BarrelCandidate(key);
        if (barrel == null || solids.Any(p => Vector2.Distance(p.Position, barrel.Position) < p.Radius * 1.04f + 180) ||
            places.Any(p => Vector2.Distance(p.Position, barrel.Position) < p.Radius + 150)) return;
        // Neighbor candidates determine spacing even when their chunks are unloaded.
        for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++)
        {
            if (x == 0 && y == 0) continue;
            var other = BarrelCandidate(new(key.X + x, key.Y + y));
            if (other != null && Vector2.DistanceSquared(other.Position, barrel.Position) < BarrelSpacing * BarrelSpacing &&
                (other.Style < barrel.Style || (other.Style == barrel.Style && (y < 0 || (y == 0 && x < 0))))) return;
        }
        places.Add(barrel);
    }
    public OceanChunk Generate(ChunkKey key)
    {
        if (StartingArea.Contains(key)) return StartingArea.Generate(key);
        var places = Landmarks(key).ToList();
        // Include distant prison shores when placing nearby encounters and barrels.
        var nearbySolids = new List<Place>();
        for (int y = -2; y <= 2; y++) for (int x = -2; x <= 2; x++)
        {
            var neighbor = new ChunkKey(key.X + x, key.Y + y);
            nearbySolids.AddRange(StartingArea.Contains(neighbor)
                ? StartingArea.Generate(neighbor).Places.Where(IsSolid) : Landmarks(neighbor));
        }
        var island = places.FirstOrDefault(p => p.Kind == PlaceKind.Island);
        if (island != null && IslandTreasure(island) is { } treasure) places.Add(treasure);
        AddEncounters(key, places, nearbySolids);
        AddBarrel(key, places, nearbySolids);
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
        if(rng.Unit()<.35f && TryPosition(150,out var current)) Add(PlaceKind.Current,current,245);
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
        // Choose a stable tangent before contact so chasing enemies can round an island.
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
    public static Vector2 Unit(Vector2 v, Vector2 fallback = default) => v.LengthSquared() > .0001f ? Vector2.Normalize(v) : fallback;
}
