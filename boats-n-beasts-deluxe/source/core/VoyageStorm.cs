using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed class LightningStrike(Vector2 position)
{
    public const float Radius = 152;
    public const float Windup = 1.72f;
    public Vector2 Position { get; } = position;
    public float Remaining { get; internal set; } = Windup;
    internal bool Threatened { get; set; }
}

public sealed partial class Voyage
{
    const float StrikeInterval = 19;
    float nextStrike = 18;
    bool markWake = true;
    public LightningStrike? StormStrike { get; private set; }
    public int StormKills { get; private set; }

    void UpdateStorm(float dt)
    {
        if (Charter != Charter.Stormchaser) return;
        if (BossSpawned)
        {
            StormStrike = null;
            return;
        }
        if (StormStrike is not { } strike)
        {
            if (CombatTime < nextStrike) return;
            MarkStormStrike();
            return;
        }

        strike.Threatened |= WasInLateBlast(strike.Position, LightningStrike.Radius, strike.Remaining);
        strike.Remaining = Math.Max(0, strike.Remaining - dt);
        if (strike.Remaining > 0) return;

        nextStrike = CombatTime + StrikeInterval;
        Events.Add(new("stormStrike", strike.Position));
        ResolveBlast(strike.Position, LightningStrike.Radius, 26, strike.Threatened, HullHit.Lightning);
        int before = StormKills;
        SplashEnemies(strike.Position, LightningStrike.Radius, 62);
        StormStrike = null;
        int caught = StormKills - before;
        if (caught > 0) Events.Add(new("stormKills", strike.Position, caught));
    }

    void CreditStormKill(Enemy enemy)
    {
        if (BossSpawned || StormStrike is not { } strike ||
            Vector2.DistanceSquared(enemy.Position, strike.Position) >= LightningStrike.Radius * LightningStrike.Radius) return;
        StormKills++;
        if (strike.Remaining > 0) Events.Add(new("stormCrewKill", enemy.Position));
    }

    void MarkStormStrike()
    {
        var lead = Velocity * .65f;
        if (lead.LengthSquared() > 220 * 220) lead = OceanWorld.Unit(lead) * 220;
        var wake = Position + lead;
        var target = wake;
        if (!markWake)
        {
            var pursuer = Enemies.Where(e => e.Health > 0 && !e.Emerging &&
                    Vector2.DistanceSquared(e.Position, wake) <= 600 * 600)
                .MinBy(e => Vector2.DistanceSquared(e.Position, wake));
            if (pursuer == null && CombatTime < nextStrike + 6) return;
            if (pursuer != null)
            {
                var predicted = pursuer.Position + pursuer.Velocity * (LightningStrike.Windup * .72f);
                target = World.Slide(pursuer.Position, predicted, 26);
            }
        }
        if (!World.IsWater(target, 20)) target = World.IsWater(wake, 20) ? wake : Position;
        markWake = !markWake;
        StormStrike = new(target);
        Events.Add(new("stormWarning", target));
    }
}
