using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed partial class Voyage
{
    public Vector2 CannonAim { get; private set; }
    public Vector2 HarpoonAim { get; private set; }

    void FireDeckWeapon(WeaponKind weapon, Enemy target, Vector2 pivot, int rank, WeaponStats stats)
    {
        var fitting = BoatRig.Mount(Boat, Weapons, weapon);
        bool cannon = weapon == WeaponKind.Cannon;
        float speed = cannon ? 650 : 580;
        var offset = target.Position - pivot;
        float ahead = Vector2.Dot(offset, target.Velocity);
        float speedGap = speed * speed - target.Velocity.LengthSquared();
        float flight = speedGap > 1
            ? (ahead + MathF.Sqrt(ahead * ahead + speedGap * offset.LengthSquared())) / speedGap
            : offset.Length() / speed;
        var aim = target.Position + target.Velocity * Math.Min(flight, 1.5f);
        if (!World.OpenShot(pivot, aim)) aim = target.Position;
        var direction = OceanWorld.Unit(aim - pivot, Forward);
        var side = new Vector2(-direction.Y, direction.X);
        if (cannon) CannonAim = direction;
        else HarpoonAim = direction;

        float barrelScale = fitting.Size * (1 + .035f * Math.Min(5, rank - 1));
        float advance = Math.Min(.274f * BoatRig.Scale.Z * 100 * barrelScale,
            Math.Max(0, Vector2.Distance(pivot, target.Position) - 4));
        var muzzle = pivot + direction * advance;
        float height = (fitting.Position.Y + .112f * barrelScale) * BoatRig.Scale.Y;
        int count = stats.Projectiles;
        for (int i = 0; i < count; i++)
        {
            var start = muzzle + side * ((i - (count - 1) / 2f) * 9);
            Shots.Add(new()
            {
                Kind = weapon, Position = start, Previous = start, Velocity = direction * speed,
                Damage = stats.Damage, Life = cannon ? 2.4f : 1.15f * Area, Radius = 6, LaunchHeight = height,
                Pierce = stats.Targets - 1, Bounces = stats.Ricochets
            });
        }
        Events.Add(new(cannon ? "shot" : "harpoon", muzzle, height));
    }

    Vector2 DeckPivot(WeaponKind kind)
    {
        var mount = BoatRig.Mount(Boat, Weapons, kind).Position * BoatRig.Scale * 100;
        var forward = Forward;
        return Position + new Vector2(-forward.Y, forward.X) * mount.X - forward * mount.Z;
    }
}
