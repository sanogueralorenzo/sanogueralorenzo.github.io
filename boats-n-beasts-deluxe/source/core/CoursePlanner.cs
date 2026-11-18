using System.Numerics;
namespace BoatsNBeasts.Core;

static class CoursePlanner
{
    public const float LegLength = 1700;
    internal const float Clearance = 92;
    const float GridStep = 96;
    const int GridRadius = 24;
    const int Width = 2 * GridRadius + 1;
    const int CellCount = Width * Width;
    static readonly (int X, int Y)[] Neighbors =
        [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)];

    public static Vector2[] Plan(OceanWorld world, Vector2 from, Vector2 target)
    {
        var solids = world.Places.Where(OceanWorld.IsSolid).ToArray();
        var origin = ClearWater(world, from);
        var goal = ClearWater(world, target);
        if (!WaterAt(solids, origin) || !WaterAt(solids, goal)) return [];
        if (SegmentClear(solids, origin, goal)) return origin == from ? [goal] : [origin, goal];

        var route = Search(solids, origin, goal);
        if (route.Count == 0) return [];

        var course = new List<Vector2>();
        if (origin != from) course.Add(origin);
        var last = origin;
        int first = 0;
        while (first < route.Count)
        {
            int farthest = route.Count - 1;
            while (farthest > first && !SegmentClear(solids, last, route[farthest])) farthest--;
            last = route[farthest];
            course.Add(last);
            first = farthest + 1;
        }
        return course.ToArray();
    }

    static Vector2 ClearWater(OceanWorld world, Vector2 point)
    {
        for (int i = 0; i < 3 && !world.IsWater(point, Clearance); i++)
            point = world.Slide(point, point, Clearance + 15);
        return point;
    }

    static List<Vector2> Search(Place[] solids, Vector2 start, Vector2 goal)
    {
        int center = GridRadius * Width + GridRadius;
        Vector2 Point(int index) => start + new Vector2(index % Width - GridRadius, index / Width - GridRadius) * GridStep;
        var frontier = new PriorityQueue<int, float>();
        var costs = new float[CellCount];
        var previous = new int[CellCount];
        var seen = new bool[CellCount];
        var water = new sbyte[CellCount];
        Array.Fill(costs, float.PositiveInfinity);
        costs[center] = 0;
        frontier.Enqueue(center, Vector2.Distance(start, goal));
        while (frontier.TryDequeue(out int cell, out _))
        {
            if (seen[cell]) continue;
            seen[cell] = true;
            var point = Point(cell);
            if (Vector2.DistanceSquared(point, goal) < 4 * GridStep * GridStep && SegmentClear(solids, point, goal))
            {
                var path = new List<Vector2> { goal };
                for (int at = cell; at != center; at = previous[at]) path.Add(Point(at));
                path.Reverse();
                return path;
            }

            int x = cell % Width, y = cell / Width;
            foreach (var (dx, dy) in Neighbors)
            {
                int nx = x + dx, ny = y + dy;
                if (nx < 0 || nx >= Width || ny < 0 || ny >= Width) continue;
                int neighbor = ny * Width + nx;
                if (seen[neighbor]) continue;
                float cost = costs[cell] + (dx == 0 || dy == 0 ? GridStep : GridStep * 1.41421356f);
                if (cost >= costs[neighbor]) continue;
                var next = Point(neighbor);
                if (water[neighbor] == 0) water[neighbor] = WaterAt(solids, next) ? (sbyte)1 : (sbyte)-1;
                if (water[neighbor] < 0 || !SegmentClear(solids, point, next)) continue;
                costs[neighbor] = cost;
                previous[neighbor] = cell;
                frontier.Enqueue(neighbor, cost + Vector2.Distance(next, goal));
            }
        }
        return [];
    }

    static bool WaterAt(Place[] solids, Vector2 point)
    {
        foreach (var solid in solids)
            if (OceanWorld.Overlap(solid, point, Clearance, out _, out _)) return false;
        return true;
    }

    static bool SegmentClear(Place[] solids, Vector2 start, Vector2 end) =>
        OceanWorld.ClearSegment(solids, start, end, Clearance, 32);
}
