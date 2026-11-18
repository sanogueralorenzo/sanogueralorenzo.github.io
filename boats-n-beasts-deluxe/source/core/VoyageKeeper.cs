using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed partial class Voyage
{
    const float KeeperRange = 365, KeeperLungeSpeed = 485, KeeperWindup = 1.16f, KeeperOpening = 1.8f;

    void UpdateKeeper(Enemy keeper, Vector2 anchor, Vector2 toward, float distance, float dt)
    {
        keeper.Exposed = Math.Max(0, keeper.Exposed - dt);
        if (keeper.Charge is { } charge)
        {
            var before = keeper.Position;
            bool rushing = keeper.Dash > 0;
            if (charge.Advance(keeper, dt))
            {
                keeper.Exposed = KeeperOpening;
                keeper.AttackClock = KeeperOpening + .72f;
                Events.Add(new("keeperOpening", keeper.Position));
            }
            if (rushing && SegmentDistance(Position, before, keeper.Position) < keeper.ContactRadius)
                DamagePlayer(17, HullHit.Keeper);
            return;
        }

        if (keeper.Exposed > 0) return;
        bool away = Vector2.DistanceSquared(Position, anchor) > 605 * 605;
        if (!away && keeper.AttackClock <= 0 && distance <= KeeperRange + keeper.ContactRadius * .6f)
        {
            keeper.Direction = toward;
            keeper.Charge = BeastCharge.Aim(World, keeper.Position, toward, keeper.Radius,
                KeeperWindup, KeeperRange, KeeperLungeSpeed);
            keeper.Telegraph = KeeperWindup;
            Events.Add(new("keeperWindup", keeper.Position));
            return;
        }

        var home = anchor - keeper.Position;
        if (away && home.LengthSquared() <= 80 * 80) return;
        float speed = keeper.SwimSpeed * .72f;
        var motion = away ? OceanWorld.Unit(home) : distance < 145 ? -toward : toward;
        if (!away && keeper.Pull > 0) motion += HarpoonForce(keeper, dt) / speed;
        motion = World.Avoid(keeper.Position, motion, keeper.Radius, keeper.Id);
        keeper.Position = World.Slide(keeper.Position, keeper.Position + motion * speed * dt, keeper.Radius);
    }
}
