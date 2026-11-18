using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed class DriftingCache(Vector2 position, Vector2 drift)
{
    public const float Lifetime = 17;
    public const float PickupRadius = 88;
    public const int RewardXp = 7;
    public Vector2 Position { get; internal set; } = position;
    public Vector2 Velocity { get; internal set; } = drift;
    internal Vector2 Drift { get; } = drift;
    public float Remaining { get; internal set; } = Lifetime;
}

public sealed partial class Voyage
{
    bool cacheLaunched;
    float nextCacheSearch;
    public DriftingCache? FloatingCache { get; private set; }
    public bool FloatingCacheClaimed { get; private set; }

    void UpdateDriftingCache(float dt)
    {
        if (BossSpawned) return;
        if (FloatingCache is not { } cache)
        {
            bool due = CombatTime >= 36 || BeaconsLit > 0 && CombatTime >= 18;
            if (!cacheLaunched && due && CombatTime >= nextCacheSearch)
                LaunchCache();
            return;
        }

        var current = World.FlowAt(cache.Position);
        var wanted = cache.Position + (cache.Drift + current * .66f) * dt;
        var position = World.Slide(cache.Position, wanted, 30);
        cache.Velocity = (position - cache.Position) / dt;
        cache.Position = position;
        if (Vector2.DistanceSquared(Position, position) <= DriftingCache.PickupRadius * DriftingCache.PickupRadius)
        {
            FloatingCache = null;
            FloatingCacheClaimed = true;
            Xp += DriftingCache.RewardXp;
            Boost = Math.Min(100, Boost + 24);
            silver++;
            Events.Add(new("cacheCaught", position, DriftingCache.RewardXp));
            return;
        }

        cache.Remaining -= dt;
        if (cache.Remaining > 0) return;
        FloatingCache = null;
        Events.Add(new("cacheSank", position));
    }

    void LaunchCache()
    {
        var search = new SeedRandom(SeedRandom.Hash(World.Seed, (int)CombatTime, BeaconsLit, 0x63616368u));
        float angle = search.Range(0, MathF.Tau);
        for (int i = 0; i < 14; i++)
        {
            float direction = angle + i * MathF.Tau / 14;
            var offset = new Vector2(MathF.Cos(direction), MathF.Sin(direction));
            var at = Position + offset * search.Range(555, 710);
            var tangent = new Vector2(-offset.Y, offset.X) * (search.Unit() < .5f ? -1 : 1);
            var drift = (tangent - offset * .2f) * 108;
            if (!World.IsWater(at, CoursePlanner.Clearance + 20) ||
                !World.OpenApproach(at, at + drift * 2.6f, CoursePlanner.Clearance)) continue;

            FloatingCache = new(at, drift);
            cacheLaunched = true;
            Events.Add(new("cacheSpotted", at));
            return;
        }
        nextCacheSearch = CombatTime + 3;
    }
}
