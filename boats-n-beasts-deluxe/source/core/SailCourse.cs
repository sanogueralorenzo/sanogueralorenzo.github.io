using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed class SailCourse
{
    Vector2[] waypoints = [];
    IReadOnlyList<Place>? chart;
    int next;
    int patrolStart;
    bool continuing;
    Place? supply;
    DriftingCache? pursuit;
    float pursuitRefresh;

    public Vector2? Destination { get; private set; }
    public Beacon? BeaconTarget { get; private set; }
    public Beacon? Patrol => BeaconTarget is { Objective: BeaconObjective.Patrol } ? BeaconTarget : null;
    public ReadOnlySpan<Vector2> Ahead => waypoints.AsSpan(next);

    public void Clear()
    {
        Destination = null;
        waypoints = [];
        chart = null;
        next = patrolStart = 0;
        BeaconTarget = null;
        supply = null;
        pursuit = null;
        continuing = false;
    }

    public bool Plot(Voyage run, Vector2 destination)
    {
        Clear();
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

    public bool Plot(Voyage run, DriftingCache cache)
    {
        if (run.FloatingCache != cache) return false;
        float intercept = Math.Clamp(Vector2.Distance(run.Position, cache.Position) / run.Speed, .28f, 2.4f);
        var aim = cache.Position + cache.Velocity * intercept;
        if (!run.World.IsWater(aim, CoursePlanner.Clearance)) aim = cache.Position;
        if (!Plot(run, aim)) return false;
        pursuit = cache;
        pursuitRefresh = run.CombatTime + .48f;
        return true;
    }

    public bool Plot(Voyage run, Place place)
    {
        if (run.World.Depletion.ContainsKey(place.Id)) return false;
        if (place.Kind == PlaceKind.Treasure)
        {
            var pickup = OceanWorld.TreasureApproach(place);
            if (!Plot(run, OceanWorld.TreasureApproach(place, 88))) return false;
            if (!continuing)
            {
                if (!run.World.OpenApproach(waypoints[^1], pickup, OceanWorld.TreasureApproachClearance))
                {
                    Clear();
                    return false;
                }
                waypoints = [..waypoints, pickup];
                Destination = pickup;
            }
        }
        else if (place.Kind == PlaceKind.Current)
        {
            if (!PlotCurrent(run, place)) return false;
        }
        else if (!Plot(run, place.Position)) return false;
        supply = place;
        return true;
    }

    bool PlotCurrent(Voyage run, Place current)
    {
        var flow = OceanWorld.FlowDirection(current);
        float reach = current.Radius;
        while (!run.World.OpenApproach(current.Position - flow * reach, current.Position + flow * reach, CoursePlanner.Clearance))
        {
            reach *= .75f;
            if (reach < current.Radius * .5f) return false;
        }

        var offset = run.Position - current.Position;
        float along = Vector2.Dot(offset, flow);
        float across = MathF.Abs(Vector2.Dot(offset, new(-flow.Y, flow.X)));
        var exit = current.Position + flow * reach;
        if (along >= -reach && along < reach &&
            across <= current.Radius * OceanWorld.CurrentWidthFactor &&
            run.World.OpenApproach(run.Position, exit, CoursePlanner.Clearance))
            return Plot(run, exit);

        var entrance = current.Position - flow * reach;
        if (!Plot(run, entrance)) return false;
        if (continuing) return true;
        if (!run.World.OpenApproach(waypoints[^1], exit, CoursePlanner.Clearance))
        {
            Clear();
            return false;
        }
        waypoints = [..waypoints, exit];
        Destination = exit;
        return true;
    }

    public bool Plot(Voyage run, Beacon beacon)
    {
        if (run.Salvage.Towing)
        {
            if (!Plot(run, beacon.Position)) return false;
            run.Salvage.Destination = beacon;
            return true;
        }
        if (beacon.Lit || beacon.Objective == BeaconObjective.Defend || run.BossSpawned)
            return Plot(run, beacon.Position);

        const float duelEntry = Beacon.Radius - 55;
        var from = OceanWorld.Unit(run.Position - beacon.Position, Vector2.UnitY);
        if (beacon.Objective == BeaconObjective.Duel)
        {
            if (AtDuel(run, beacon)) { Clear(); return true; }
            if (!Plot(run, beacon.Position + from * duelEntry)) return false;
            BeaconTarget = beacon;
            return true;
        }

        const int legs = 8;
        const float radius = Beacon.Radius * .68f;
        float step = MathF.Tau / legs;
        var entry = beacon.Position + from * radius;
        if (!Plot(run, entry)) return false;
        BeaconTarget = beacon;
        Destination = beacon.Position;
        if (continuing) return true;

        float angle = MathF.Atan2(from.Y, from.X);
        var loop = new Vector2[legs];
        for (int i = 0; i < legs; i++)
        {
            float turn = angle + step * (i + 1);
            loop[i] = beacon.Position + new Vector2(MathF.Cos(turn), MathF.Sin(turn)) * radius;
        }
        patrolStart = waypoints.Length;
        waypoints = [..waypoints, ..loop];
        return true;
    }

    static bool AtDuel(Voyage run, Beacon beacon) =>
        Vector2.DistanceSquared(run.Position, beacon.Position) <= (Beacon.Radius - 7) * (Beacon.Radius - 7);

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
        if (supply is { } store && run.World.Depletion.ContainsKey(store.Id))
        {
            Clear();
            return input;
        }
        if (pursuit is { } cache)
        {
            if (run.FloatingCache != cache)
            {
                Clear();
                return input;
            }
            if ((run.CombatTime >= pursuitRefresh || !ReferenceEquals(chart, run.World.Places)) && !Plot(run, cache))
                return input;
        }
        else if (BeaconTarget is { } beacon)
        {
            bool duel = beacon.Objective == BeaconObjective.Duel;
            if (beacon.Lit || run.BossSpawned || (duel && AtDuel(run, beacon)))
            {
                Clear();
                return input;
            }
            if ((duel || continuing || next < patrolStart) && !ReferenceEquals(chart, run.World.Places) &&
                !Plot(run, beacon)) return input;
        }
        else if (!ReferenceEquals(chart, run.World.Places))
        {
            bool clearPickup = supply?.Kind == PlaceKind.Treasure && !continuing && next == waypoints.Length - 1 &&
                run.World.OpenApproach(run.Position, destination, OceanWorld.TreasureApproachClearance);
            if (clearPickup) chart = run.World.Places;
            else if (!ReplotPoint(run, destination)) return input;
        }

        while (next < waypoints.Length)
        {
            var offset = waypoints[next] - run.Position;
            bool circling = Patrol != null && !continuing && next >= patrolStart;
            bool last = !circling && next == waypoints.Length - 1;
            float reach = last ? supply == null ? 29 : 9 : circling ? 49 : 42;
            bool reached = offset.LengthSquared() <= reach * reach;
            if (reached && !last && offset.LengthSquared() > 12 * 12)
                reached = run.World.IsWater(run.Position, CoursePlanner.Clearance);
            if (!reached)
            {
                float distance = offset.Length();
                var direction = offset / distance;
                float throttle = circling ? .86f : Math.Clamp(distance / (last ? 164 : 125), .20f, 1);
                bool boost = !run.Salvage.Towing && !circling && input.Boost && distance > 205 &&
                    Vector2.Dot(run.Forward, direction) > .86f;
                bool sprint = boost && !run.BoostExhausted && (run.IsBoosting ? run.Boost > 0 : run.Boost >= 8);
                var flow = run.World.FlowAt(run.Position);
                var drift = flow - direction * Math.Max(0, Vector2.Dot(flow, direction));
                var move = direction * throttle - drift / (run.Speed * (sprint ? 2.05f : 1));
                return input with { Move = move, Boost = boost };
            }
            next++;
            if (circling && next == waypoints.Length) next = patrolStart;
        }

        if (pursuit is { } approaching)
        {
            Plot(run, approaching);
            return input;
        }
        if (BeaconTarget is { } pendingBeacon && (Patrol != null || continuing))
        {
            Plot(run, pendingBeacon);
            return input;
        }
        if (continuing && Vector2.DistanceSquared(run.Position, destination) > 58 * 58)
        {
            ReplotPoint(run, destination);
            return input;
        }
        Clear();
        return input;
    }

    bool ReplotPoint(Voyage run, Vector2 destination) => supply is { } place ? Plot(run, place) : Plot(run, destination);
}
