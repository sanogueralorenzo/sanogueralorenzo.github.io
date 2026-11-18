using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed partial class Voyage
{
    public const float BlastHullMargin = 23;
    public const float CloseCallWindow = .42f;
    public const float CloseCallBoost = 16;
    public int CloseCalls { get; private set; }
    Vector2 beforeHelm;
    bool escapedBlast, damagedThisTick;
    float closeCallCooldown;

    void BeginCloseCallTick(float dt)
    {
        beforeHelm = Position;
        escapedBlast = damagedThisTick = false;
        closeCallCooldown = Math.Max(0, closeCallCooldown - dt);
    }

    bool WasInLateBlast(Vector2 center, float radius, float remaining)
    {
        if (remaining > CloseCallWindow) return false;
        float reach = radius + BlastHullMargin;
        return Vector2.DistanceSquared(beforeHelm, center) < reach * reach ||
            Vector2.DistanceSquared(Position, center) < reach * reach;
    }

    bool ResolveBlast(Vector2 center, float radius, float damage, bool threatened)
    {
        float reach = radius + BlastHullMargin;
        if (Vector2.DistanceSquared(Position, center) >= reach * reach)
        {
            escapedBlast |= threatened;
            return false;
        }

        float before = Health;
        DamagePlayer(damage);
        return Health < before;
    }

    void RewardCloseCall()
    {
        if (!escapedBlast || damagedThisTick || Health <= 0 || closeCallCooldown > 0) return;
        closeCallCooldown = .9f;
        float restored = Math.Min(CloseCallBoost, 100 - Boost);
        Boost += restored;
        if (ChainTime > 0) ChainTime = Math.Min(ChainDuration, ChainTime + 1.25f);
        CloseCalls++;
        Events.Add(new("closeCall", Position, restored));
    }
}
