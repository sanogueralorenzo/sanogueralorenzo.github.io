using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed partial class BluewaterCourse
{
    void RouteAroundShoal(FleetBoat boat, Vector2 destination)
    {
        bool Clear(Vector2 p) => Ship.World.IsWater(p, 26) && (Phase != ChartPhase.Running || !banks.Any(b => !b.Broken && Vector2.DistanceSquared(p, b.Closest(p)) < (b.Width + 24) * (b.Width + 24)));
        if (ShoalRoute.Plot(boat.Position, destination, Clear, boat.Detour))
        {
            boat.Wake.Clear();
            boat.LastLead = destination;
        }
    }
}

internal static class ShoalRoute
{
    internal static bool Plot(Vector2 origin, Vector2 destination, Func<Vector2, bool> clear, Queue<Vector2> route)
    {
        const int reach = 13;
        const float spacing = 60;
        var start = (X: 0, Y: 0);
        var best = start;
        var queue = new PriorityQueue<(int X, int Y), float>();
        var costs = new Dictionary<(int, int), float> { { start, 0 } };
        var parents = new Dictionary<(int, int), (int, int)>();
        Vector2 Point((int X, int Y) cell) => origin + new Vector2(cell.X, cell.Y) * spacing;
        float bestDistance = Vector2.Distance(origin, destination);
        queue.Enqueue(start, bestDistance);
        while (queue.TryDequeue(out var cell, out _))
        {
            var here = Point(cell);
            float remaining = Vector2.Distance(here, destination);
            if (remaining < bestDistance)
            {
                best = cell; bestDistance = remaining;
                if (remaining < 74) break;
            }
            for (int dx = -1; dx <= 1; dx++)
                for (int dy = -1; dy <= 1; dy++)
                {
                    if (dx == 0 && dy == 0) continue;
                    var next = (X: cell.X + dx, Y: cell.Y + dy);
                    if (Math.Abs(next.X) > reach || Math.Abs(next.Y) > reach) continue;
                    var p = Point(next);
                    float cost = costs[cell] + (dx == 0 || dy == 0 ? spacing : spacing * 1.4142f);
                    if (costs.TryGetValue(next, out var old) && old <= cost) continue;
                    if (!clear(p) || !clear(Vector2.Lerp(here, p, .5f))) continue;
                    costs[next] = cost; parents[next] = cell;
                    queue.Enqueue(next, cost + Vector2.Distance(destination, p));
                }
        }
        if (best == start) return false;
        var bends = new Stack<Vector2>();
        for (var cursor = best; cursor != start; cursor = parents[cursor]) bends.Push(Point(cursor));
        route.Clear();
        foreach (var bend in bends) route.Enqueue(bend);
        return true;
    }
}
