using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed class SailCourse
{
    Vector2[] waypoints = [];
    IReadOnlyList<Place>? chart;
    int next;
    bool continuing;

    public Vector2? Destination { get; private set; }
    public ReadOnlySpan<Vector2> Ahead => waypoints.AsSpan(next);

    public void Clear()
    {
        Destination = null;
        waypoints = [];
        chart = null;
        next = 0;
        continuing = false;
    }

    public bool Plot(Voyage run, Vector2 destination)
    {
        var world = run.World;
        var offset = destination - run.Position;
        continuing = offset.LengthSquared() > CoursePlanner.LegLength * CoursePlanner.LegLength;
        var plan = continuing ? PlotLeg(run, offset) : CoursePlanner.Plan(world, run.Position, destination);
        if (plan.Length == 0)
        {
            Clear();
            return false;
        }
        chart = world.Places;
        waypoints = plan;
        next = 0;
        Destination = continuing ? destination : plan[^1];
        return true;
    }

    static Vector2[] PlotLeg(Voyage run, Vector2 offset)
    {
        var bearing = OceanWorld.Unit(offset);
        var aim = run.Position + bearing * CoursePlanner.LegLength;
        var plan = CoursePlanner.Plan(run.World, run.Position, aim);
        if (MakesProgress(plan)) return plan;

        var side = new Vector2(-bearing.Y, bearing.X);
        var first = CoursePlanner.Plan(run.World, run.Position, aim + side * 590);
        var second = CoursePlanner.Plan(run.World, run.Position, aim - side * 590);
        if (!MakesProgress(first)) return MakesProgress(second) ? second : [];
        if (!MakesProgress(second)) return first;
        var destination = run.Position + offset;
        return Vector2.DistanceSquared(first[^1], destination) <= Vector2.DistanceSquared(second[^1], destination)
            ? first : second;

        bool MakesProgress(Vector2[] path) => path.Length > 0 &&
            Vector2.Dot(path[^1] - run.Position, bearing) > 260;
    }

    public SailInput Apply(Voyage run, SailInput input)
    {
        if (input.Move != Vector2.Zero)
        {
            Clear();
            return input;
        }
        if (Destination is not { } destination) return input;
        if (!ReferenceEquals(chart, run.World.Places) && !Plot(run, destination)) return input;

        while (next < waypoints.Length)
        {
            var offset = waypoints[next] - run.Position;
            bool last = next == waypoints.Length - 1;
            float reach = last ? 29 : 42;
            bool reached = offset.LengthSquared() <= reach * reach;
            if (reached && !last && offset.LengthSquared() > 12 * 12)
                reached = run.World.IsWater(run.Position, CoursePlanner.Clearance);
            if (!reached)
            {
                float distance = offset.Length();
                var direction = offset / distance;
                float throttle = Math.Clamp(distance / (last ? 164 : 125), .20f, 1);
                bool boost = input.Boost && distance > 205 && Vector2.Dot(run.Forward, direction) > .86f;
                bool sprint = boost && !run.BoostExhausted && (run.IsBoosting ? run.Boost > 0 : run.Boost >= 8);
                var flow = run.World.FlowAt(run.Position);
                var drift = flow - direction * Math.Max(0, Vector2.Dot(flow, direction));
                var move = direction * throttle - drift / (run.Speed * (sprint ? 2.05f : 1));
                return input with { Move = move, Boost = boost };
            }
            next++;
        }

        if (continuing && Vector2.DistanceSquared(run.Position, destination) > 58 * 58)
        {
            Plot(run, destination);
            return input;
        }
        Clear();
        return input;
    }
}
