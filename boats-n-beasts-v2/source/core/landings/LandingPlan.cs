using System.Numerics;

namespace BoatsNBeasts.Core;

public enum YardTerrain { Quarry, Lagoons, IceLead, ReedCourt, Ropewalk, Arcade, Spiral, Shoal, Terraces, Windstairs, MoonBasin, Hoopwalk }
public enum YardRoad { Planks, Stone, Rope, Shoal }
public sealed record YardPatch(string Name, Vector2 Center, Vector2 Radius, Vector2[] Rim)
{
    public Vector2 Closest(Vector2 p)
    {
        bool inside = true;
        float shortest = float.MaxValue;
        var nearest = Center;
        for (int i = 0; i < Rim.Length; i++)
        {
            var a = Rim[i]; var b = Rim[(i + 1) % Rim.Length]; var side = b - a;
            if (side.X * (p.Y - a.Y) - side.Y * (p.X - a.X) < 0) inside = false;
            var at = a + side * Math.Clamp(Vector2.Dot(p - a, side) / side.LengthSquared(), 0, 1);
            float gap = Vector2.DistanceSquared(p, at);
            if (gap < shortest) { nearest = at; shortest = gap; }
        }
        return inside ? p : nearest;
    }
}
public sealed record YardPassage(int A, int B, Vector2 From, Vector2 To, float Width, YardRoad Road)
{
    public Vector2 Closest(Vector2 p, float start = 0, float end = 1)
    {
        var axis = To - From;
        float t = Math.Clamp(Vector2.Dot(p - From, axis) / axis.LengthSquared(), start, end);
        var basePoint = From + axis * t;
        var side = Vector2.Normalize(new Vector2(-axis.Y, axis.X));
        return basePoint + side * Math.Clamp(Vector2.Dot(p - basePoint, side), -Width, Width);
    }
}

public sealed class LandingPlan
{
    public YardTerrain Terrain { get; }
    public YardPatch[] Patches { get; }
    public YardPassage[] Passages { get; }
    public Vector2 Dock { get; }
    public Vector2 Summit { get; }
    public Vector2 Campsite { get; }
    public Vector2 Gate { get; }
    public Vector2 Ferry { get; }
    public Vector2[] Locks { get; }
    public Vector2[] Bells { get; }
    public Vector2 Ledger { get; }
    public Vector2 Wayhouse { get; }
    public Vector2 Pocket { get; }
    public Vector2 LandingSteps { get; }
    public int BrokenBridge { get; private set; } = -1;
    public int Seed { get; }
    readonly HashSet<int> gates = [];
    public bool GateClosed(int passage) => gates.Contains(passage);
    readonly Vector2[] vertices;
    readonly int[][] exits;
    readonly float[,] distances;
    readonly int[,] nextHop;
    public LandingPlan(CampaignOrder order, int district, int runSeed, HiddenWorks? works = null)
    {
        uint signature = 2166136261;
        foreach (char c in order.Id) signature = unchecked((signature ^ c) * 16777619);
        Seed = unchecked((int)SeedRandom.Hash((uint)runSeed, district, order.Tier, signature));
        var random = new Random(Seed);
        var climate = LandingRegion.From(order.Region).Climate;
        YardTerrain[] family = climate switch
        {
            IslandClimate.Saltstep => [YardTerrain.Terraces, YardTerrain.ReedCourt, YardTerrain.Lagoons, YardTerrain.MoonBasin],
            IslandClimate.Bottlebrush => [YardTerrain.MoonBasin, YardTerrain.ReedCourt, YardTerrain.Windstairs, YardTerrain.Quarry],
            IslandClimate.Waxwing => [YardTerrain.Windstairs, YardTerrain.Ropewalk, YardTerrain.Terraces, YardTerrain.Spiral],
            IslandClimate.Narrows => [YardTerrain.Hoopwalk, YardTerrain.Lagoons, YardTerrain.ReedCourt, YardTerrain.Terraces],
            IslandClimate.Tinmoon => [YardTerrain.MoonBasin, YardTerrain.Quarry, YardTerrain.IceLead, YardTerrain.Hoopwalk],
            IslandClimate.Drumskin => [YardTerrain.Hoopwalk, YardTerrain.Spiral, YardTerrain.Windstairs, YardTerrain.ReedCourt],
            IslandClimate.Pitchwake => [YardTerrain.Terraces, YardTerrain.Quarry, YardTerrain.Arcade, YardTerrain.Ropewalk],
            IslandClimate.Calving => [YardTerrain.MoonBasin, YardTerrain.Shoal, YardTerrain.Hoopwalk, YardTerrain.Lagoons],
            IslandClimate.Kiln => [YardTerrain.Quarry, YardTerrain.Arcade, YardTerrain.Lagoons, YardTerrain.Spiral],
            IslandClimate.Delta => [YardTerrain.ReedCourt, YardTerrain.Lagoons, YardTerrain.Shoal, YardTerrain.Ropewalk],
            IslandClimate.Orchard => [YardTerrain.Spiral, YardTerrain.Ropewalk, YardTerrain.ReedCourt, YardTerrain.Lagoons],
            IslandClimate.Shelf => [YardTerrain.IceLead, YardTerrain.Lagoons, YardTerrain.Quarry, YardTerrain.Shoal],
            IslandClimate.Loom => [YardTerrain.Ropewalk, YardTerrain.ReedCourt, YardTerrain.Arcade, YardTerrain.Spiral],
            IslandClimate.Reef => [YardTerrain.Shoal, YardTerrain.Spiral, YardTerrain.Lagoons, YardTerrain.IceLead],
            IslandClimate.Court => [YardTerrain.Arcade, YardTerrain.Quarry, YardTerrain.ReedCourt, YardTerrain.IceLead],
            _ => [YardTerrain.Spiral, YardTerrain.Shoal, YardTerrain.IceLead, YardTerrain.Ropewalk]
        };
        int first = order.Id == "cinder-kiln" ? 0 : (int)(signature % 4);
        Terrain = family[(district + first) % family.Length];
        var (positions, edges) = works == null ? Shape(Terrain) : HiddenWorks.Chambers(climate);
        bool mirror = (signature & 1) != 0;
        string[] names = works?.RoomNames ?? ["Landing", "West yard", "East yard", "Upper slip", "Weigh house", "Workers’ hall", "Old stores", "Outpost", "Lower cut", "Gallery", "Back stair"];
        Patches = new YardPatch[positions.Length];
        for (int i = 0; i < Patches.Length; i++)
        {
            var def = positions[i]; var center = new Vector2((mirror ? -1 : 1) * def.X + (random.NextSingle() - .5f) * 1.1f, def.Y + (random.NextSingle() - .5f) * 1.15f);
            float size = .9f + random.NextSingle() * .17f;
            Vector2 radius = new(def.Z * size, def.W * size);
            bool paved = Terrain is YardTerrain.Arcade or YardTerrain.ReedCourt or YardTerrain.Terraces || Terrain == YardTerrain.Quarry && i % 2 == 1;
            int n = paved ? 8 : 12;
            var rim = new Vector2[n];
            for (int k = 0; k < n; k++)
            {
                float a = (k + .5f) * MathF.Tau / n;
                var unit = new Vector2(MathF.Cos(a), MathF.Sin(a));
                if (paved) unit /= Math.Max(Math.Abs(unit.X), Math.Abs(unit.Y));
                rim[k] = center + radius * unit;
            }
            Patches[i] = new(names[i], center, radius, rim);
        }
        var road = Terrain switch
        {
            YardTerrain.Arcade or YardTerrain.Quarry or YardTerrain.Terraces => YardRoad.Stone,
            YardTerrain.Ropewalk or YardTerrain.Spiral or YardTerrain.Windstairs => YardRoad.Rope,
            YardTerrain.Shoal or YardTerrain.IceLead or YardTerrain.MoonBasin => YardRoad.Shoal,
            _ => YardRoad.Planks
        };
        Passages = edges.Select((pair, index) =>
        {
            var a = Patches[pair.A]; var b = Patches[pair.B];
            Vector2 Mouth(YardPatch patch, Vector2 toward)
            {
                float low = 0, high = 1;
                for (int k = 0; k < 13; k++)
                {
                    float middle = (low + high) * .5f;
                    var probe = Vector2.Lerp(patch.Center, toward, middle);
                    if (Vector2.DistanceSquared(patch.Closest(probe), probe) < .0001f) low = middle; else high = middle;
                }
                return Vector2.Lerp(patch.Center, toward, low);
            }
            var from = Mouth(a, b.Center); var to = Mouth(b, a.Center);
            var axis = b.Center - a.Center;
            from = from + Vector2.Normalize(a.Center - from) * .31f;
            to = to + Vector2.Normalize(b.Center - to) * .31f;
            if (Vector2.Dot(to - from, axis) < .1f) { from = Vector2.Lerp(a.Center, b.Center, .42f); to = Vector2.Lerp(a.Center, b.Center, .58f); }
            return new YardPassage(pair.A, pair.B, from, to, .53f + random.NextSingle() * .32f, index % 4 == 3 ? YardRoad.Planks : road);
        }).ToArray();
        vertices = [.. Patches.Select(p => p.Center), .. Passages.SelectMany(p => new[] { p.From, p.To })];
        exits = Enumerable.Range(0, Patches.Length).Select(id => Enumerable.Range(Patches.Length, Passages.Length * 2)
            .Where(node => { int slot = node - Patches.Length; var road = Passages[slot / 2]; return (slot % 2 == 0 ? road.A : road.B) == id; }).Append(id).ToArray()).ToArray();
        distances = new float[vertices.Length, vertices.Length]; nextHop = new int[vertices.Length, vertices.Length];
        if (works == null && district > 0)
        {
            foreach (int candidate in Enumerable.Range(0, Passages.Length).OrderBy(_ => random.Next()))
            {
                if (Vector2.Distance(Passages[candidate].From, Passages[candidate].To) < 2.6f) continue;
                BrokenBridge = candidate; RebuildRoutes();
                if (Enumerable.Range(0, Patches.Length).All(i => float.IsFinite(distances[0, i]))) break;
                BrokenBridge = -1;
            }
        }
        if (works != null) foreach (int lockIndex in new[] { 2, 3, 4, 7, 8, 9, 10, 11 }) gates.Add(lockIndex);
        RebuildRoutes();
        Dock = Patches[0].Center + new Vector2(-.6f, Patches[0].Radius.Y * .52f);
        LandingSteps = Patches[0].Center + new Vector2(.9f, -.65f);
        Bells = [Patches[1].Center, Patches[2].Center];
        Summit = Patches[3].Center;
        Campsite = Summit + new Vector2(-Patches[3].Radius.X * .64f, -.49f);
        Gate = Summit + new Vector2(.15f, -Patches[3].Radius.Y * .53f);
        Locks = [Summit + new Vector2(-2.55f, .44f), Summit + new Vector2(2.55f, .44f)];
        Ferry = Patches[3].Closest(Summit + new Vector2(Patches[3].Radius.X * 1.15f, -.85f));
        Ledger = Patches[4].Center; Wayhouse = Patches[5].Center; Pocket = Patches[6].Center;
    }
    static (Vector4[] Positions, (int A, int B)[] Edges) Shape(YardTerrain t) => t switch
    {
        YardTerrain.Terraces => ([new(-11, 9, 3.4f, 2.23f), new(-12, -1, 3.4f, 2.8f), new(2, 8, 3.4f, 2.7f), new(11, -12, 5.1f, 3.89f), new(0, -1, 2.8f, 2.15f), new(9, 3, 2.8f, 3.0f), new(-13, -13, 2.43f, 1.95f), new(-6, -8, 3.1f, 1.9f), new(5, -7, 2.53f, 1.92f)], [(0, 1), (0, 2), (1, 4), (2, 5), (1, 7), (7, 6), (7, 8), (8, 3), (5, 8), (5, 4), (4, 8)]),
        YardTerrain.Windstairs => ([new(-11, 12, 3.4f, 2.8f), new(-3, 9, 3.2f, 2.65f), new(-11, -1, 3.45f, 2.8f), new(13, -7, 5.2f, 3.81f), new(0, 0, 2.8f, 2.5f), new(7, 8, 3.1f, 2.85f), new(-6, -15, 2.4f, 2.3f), new(-4, -8, 2.93f, 1.92f), new(8, 0, 2.2f, 1.83f)], [(0, 1), (0, 2), (2, 7), (7, 6), (7, 4), (7, 3), (1, 5), (5, 8), (8, 3), (1, 4), (4, 8)]),
        YardTerrain.MoonBasin => ([new(-2, 10, 3.25f, 2.7f), new(-11, 3, 3.3f, 3.1f), new(8, 6, 3.45f, 2.7f), new(-1, -15, 5.2f, 3.70f), new(-1, -2, 2.67f, 2.10f), new(10, -4, 2.85f, 2.87f), new(18, -9, 2.13f, 1.72f), new(-10, -7, 2.6f, 2.1f), new(5, -10, 2.2f, 1.71f)], [(0, 1), (0, 2), (1, 7), (7, 3), (2, 5), (5, 6), (5, 8), (8, 3), (1, 4), (4, 5), (4, 8)]),
        YardTerrain.Hoopwalk => ([new(1, 12, 3.3f, 2.61f), new(-9, 8, 3.51f, 2.61f), new(8, -2, 3.2f, 2.88f), new(-7, -13, 5.2f, 3.78f), new(-3, -1, 2.74f, 2.3f), new(10, 8, 2.65f, 2.94f), new(-19, 1, 2.10f, 1.77f), new(-11, -3, 2.33f, 2.13f), new(3, -9, 2.55f, 2.12f)], [(0, 1), (0, 5), (5, 2), (2, 8), (8, 3), (1, 7), (7, 3), (7, 6), (1, 4), (4, 2), (4, 8)]),
        YardTerrain.Quarry => ([new(-7, 6, 3.6f, 2.6f), new(-7, -3, 3.4f, 2.65f), new(5, 5, 3.2f, 2.65f), new(1, -15, 4.9f, 3.7f), new(-.8f, -4, 2.6f, 2.25f), new(7, -5, 2.8f, 3.4f), new(-11, -12, 2.15f, 2.1f), new(-5, -10, 1.8f, 1.65f)], [(0, 1), (0, 2), (1, 4), (2, 5), (4, 5), (1, 7), (7, 3), (5, 3), (7, 6), (4, 2)]),
        YardTerrain.IceLead => ([new(0, 6, 3.8f, 2.7f), new(-5, -4, 2.75f, 4.6f), new(4, -9, 2.9f, 4.5f), new(-2, -19, 5.0f, 3.7f), new(5, 1, 2.35f, 2.6f), new(-5, -13, 2.3f, 2.65f), new(10, -15, 2.1f, 1.5f), new(-1, -6, 1.2f, 1.9f), new(-4, 2, 1.46f, 1.45f)], [(0, 8), (8, 1), (0, 4), (4, 2), (1, 7), (7, 2), (1, 5), (2, 3), (5, 3), (2, 6)]),
        YardTerrain.ReedCourt => ([new(-5, 5, 3.2f, 3.0f), new(-7, -3, 3.4f, 3.35f), new(5, -3, 3.2f, 3.1f), new(4, -14, 5.1f, 3.7f), new(-1, -2, 2.20f, 2.35f), new(0, 5, 2.5f, 2.2f), new(-11, -9, 2, 2), new(-5, -10, 2.5f, 1.8f)], [(0, 1), (0, 5), (5, 2), (5, 4), (1, 4), (4, 2), (1, 7), (7, 3), (2, 3), (7, 6)]),
        YardTerrain.Ropewalk => ([new(-9, 1, 3.15f, 2.7f), new(-3, 5, 3.2f, 2.6f), new(1, -9, 3.2f, 2.6f), new(12, -6, 4.8f, 3.7f), new(1, -1, 2.3f, 2.05f), new(7, 4, 2.35f, 2.55f), new(-5, -13, 2, 1.6f), new(-6, -5, 1.5f, 1.9f), new(7, -6, 1.9f, 1.75f)], [(0, 1), (0, 7), (7, 2), (1, 4), (4, 2), (1, 5), (2, 8), (8, 3), (5, 3), (2, 6), (4, 8)]),
        YardTerrain.Arcade => ([new(-9, 4, 3.6f, 2.8f), new(-5, -5, 3.15f, 3.1f), new(5, 4, 3.25f, 2.75f), new(10, -8, 4.8f, 3.67f), new(0, -1, 2.15f, 2.15f), new(-1, 5, 2.6f, 2.0f), new(-4, -12, 2.2f, 2f), new(3, -8, 2.1f, 2.2f)], [(0, 1), (0, 5), (5, 2), (5, 4), (4, 1), (4, 2), (1, 7), (7, 3), (2, 3), (1, 6), (4, 7)]),
        YardTerrain.Spiral => ([new(2, 8, 3.45f, 2.6f), new(-6, 2, 3.5f, 2.75f), new(6, -3, 3.3f, 2.85f), new(-4, -11, 4.9f, 3.74f), new(-1, -2, 2.6f, 2.22f), new(8, 4, 2.2f, 2.25f), new(-12, -5, 2.2f, 1.7f), new(3, -10, 2.17f, 2.0f)], [(0, 1), (0, 5), (5, 2), (2, 7), (7, 3), (1, 4), (4, 2), (4, 3), (1, 6)]),
        YardTerrain.Shoal => ([new(0, 7, 4.1f, 2.8f), new(-8, -1, 3.45f, 2.91f), new(8, -1, 3.3f, 2.9f), new(1, -13, 5.1f, 3.7f), new(-.5f, -3, 3.75f, 2.1f), new(1, 2, 1.65f, 1.9f), new(13, -7, 1.9f, 1.76f), new(-6, -8, 1.85f, 1.65f), new(6, -9, 1.9f, 1.74f)], [(0, 5), (5, 4), (4, 1), (4, 2), (0, 1), (0, 2), (1, 7), (7, 3), (2, 8), (8, 3), (8, 6)]),
        _ => ([new(7, 6, 3.7f, 2.8f), new(-5, 5, 3.2f, 2.7f), new(5, -6, 3.35f, 2.85f), new(-7, -13, 5.05f, 3.7f), new(-1, -2, 2.3f, 2.15f), new(8, 0, 2.1f, 2.45f), new(10, -13, 1.95f, 1.9f), new(-7, -4, 1.85f, 2.2f)], [(0, 1), (0, 5), (5, 2), (1, 4), (4, 2), (1, 7), (7, 3), (2, 3), (2, 6), (4, 7)])
    };
    void RebuildRoutes()
    {
        int n = vertices.Length;
        for (int a = 0; a < n; a++) for (int b = 0; b < n; b++) { distances[a, b] = a == b ? 0 : float.PositiveInfinity; nextHop[a, b] = b; }
        void Connect(int a, int b) { distances[a, b] = distances[b, a] = Vector2.Distance(vertices[a], vertices[b]); }
        foreach (var group in exits) foreach (int a in group) foreach (int b in group) Connect(a, b);
        for (int i = 0; i < Passages.Length; i++) if (i != BrokenBridge && !GateClosed(i))
        {
            int left = Patches.Length + 2 * i;
            Connect(left, left + 1);
        }
        for (int k = 0; k < n; k++) for (int i = 0; i < n; i++) for (int j = 0; j < n; j++)
            if (distances[i, k] + distances[k, j] < distances[i, j])
            {
                distances[i, j] = distances[i, k] + distances[k, j];
                nextHop[i, j] = nextHop[i, k];
            }
    }
    public void OpenDoor(int from, int to)
    {
        int index = Array.FindIndex(Passages, p => p.A == from && p.B == to || p.A == to && p.B == from);
        if (index >= 0 && gates.Remove(index)) RebuildRoutes();
    }
    public void Splice() { BrokenBridge = -1; RebuildRoutes(); }
    public Vector2 Walkable(Vector2 p)
    {
        var closest = p; float distance = float.PositiveInfinity;
        foreach (var patch in Patches)
        {
            var delta = Vector2.Abs(p - patch.Center) - patch.Radius;
            if (delta.X > 0 && delta.X * delta.X > distance || delta.Y > 0 && delta.Y * delta.Y > distance) continue;
            var at = patch.Closest(p); float d = Vector2.DistanceSquared(at, p);
            if (d < .000001f) return p;
            if (d < distance) { distance = d; closest = at; }
        }
        for (int i = 0; i < Passages.Length; i++)
        {
            var road = Passages[i]; bool closed = GateClosed(i); var at = road.Closest(p, 0, i == BrokenBridge ? .32f : closed ? .455f : 1);
            if (i == BrokenBridge || closed)
            {
                var far = road.Closest(p, closed ? .545f : .68f, 1);
                if (Vector2.DistanceSquared(far, p) < Vector2.DistanceSquared(at, p)) at = far;
            }
            float d = Vector2.DistanceSquared(at, p);
            if (d < .000001f) return p;
            if (d < distance) { distance = d; closest = at; }
        }
        return closest;
    }
    public bool CrossesDoor(Vector2 from, Vector2 to)
    {
        foreach (int index in gates)
        {
            var span = Passages[index]; var axis = Vector2.Normalize(span.To - span.From); var mid = (span.From + span.To) * .5f;
            float before = Vector2.Dot(from - mid, axis), after = Vector2.Dot(to - mid, axis);
            if (before * after > 0 || MathF.Abs(before - after) < .00001f) continue;
            var crossing = Vector2.Lerp(from, to, before / (before - after));
            if (Vector2.DistanceSquared(crossing, mid) <= (span.Width + .12f) * (span.Width + .12f)) return true;
        }
        return false;
    }
    public bool CanWalk(Vector2 a, Vector2 b)
    {
        if (CrossesDoor(a, b)) return false;
        float distance = Vector2.Distance(a, b);
        int samples = Math.Max(1, (int)MathF.Ceiling(distance * 6));
        for (int i = 1; i < samples; i++)
        {
            var p = Vector2.Lerp(a, b, i / (float)samples);
            if (Vector2.DistanceSquared(Walkable(p), p) > .0007f) return false;
        }
        return true;
    }
    public Vector2 Waypoint(Vector2 from, Vector2 goal)
    {
        goal = Walkable(goal);
        bool HasRoom(Vector2 point)
        {
            if(!CanWalk(from,point))return false;
            if(Vector2.DistanceSquared(from,point)<.36f)return true;
            var axis=Vector2.Normalize(point-from);
            var side=new Vector2(-axis.Y,axis.X)*.14f;
            var ahead=from+axis*.17f;var behind=point-axis*.17f;
            return CanWalk(ahead+side,behind+side)&&CanWalk(ahead-side,behind-side);
        }
        if(HasRoom(goal))return goal;
        var starts = Links(from); var destinations = Links(goal);
        float best = float.PositiveInfinity; int startNode = -1, endNode = -1;
        foreach (int a in starts) foreach (int b in destinations)
        {
            float cost = Vector2.Distance(from, vertices[a]) + distances[a, b] + Vector2.Distance(vertices[b], goal);
            if (cost < best) { best = cost; startNode = a; endNode = b; }
        }
        if (startNode < 0) return from;
        int n = startNode;
        while (n != endNode)
        {
            int next = nextHop[n, endNode];
            if (next == n || !HasRoom(vertices[next])) break;
            n = next;
        }
        return vertices[n];
    }
    List<int> Links(Vector2 point)
    {
        var links = new List<int>();
        for (int i = 0; i < Patches.Length; i++)
            if (Vector2.DistanceSquared(point, Patches[i].Closest(point)) < .001f) links.AddRange(exits[i]);
        for (int i = 0; i < Passages.Length; i++)
        {
            var span = Passages[i]; int left = Patches.Length + i * 2;
            if (i == BrokenBridge || GateClosed(i))
            {
                if (Vector2.DistanceSquared(span.Closest(point, 0, GateClosed(i) ? .455f : .32f), point) < .001f) links.Add(left);
                if (Vector2.DistanceSquared(span.Closest(point, GateClosed(i) ? .545f : .68f, 1), point) < .001f) links.Add(left + 1);
            }
            else if (Vector2.DistanceSquared(span.Closest(point), point) < .001f) { links.Add(left); links.Add(left + 1); }
        }
        if (links.Count == 0)
        {
            int nearest = Enumerable.Range(0, vertices.Length).MinBy(i => Vector2.DistanceSquared(vertices[i], point)); links.Add(nearest);
        }
        return links;
    }
}
