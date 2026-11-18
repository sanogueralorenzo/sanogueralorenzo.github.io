using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed class SalvageCargo(Place wreck)
{
    public const float HookRadius = 112;
    public const float DeliveryRadius = 210;
    public const float BreakLength = 310;
    public const float SlackLength = 82;
    public Vector2 Position { get; internal set; } = Mooring(wreck);
    public bool Towing { get; internal set; }
    public bool Delivered { get; internal set; }
    internal bool Disturbed { get; set; }

    public static Vector2 Mooring(Place wreck) => wreck.Position + Vector2.UnitY * (wreck.Radius * .92f);
}

public sealed partial class Voyage
{
    public SalvageCargo Salvage { get; }
    public bool SalvageAvailable => !Salvage.Delivered && !BossSpawned;
    public Vector2 TowHook => Position - Forward * 66;
    public float TowTension => Math.Clamp((Vector2.Distance(TowHook, Salvage.Position) - SalvageCargo.SlackLength) /
        (SalvageCargo.BreakLength - SalvageCargo.SlackLength), 0, 1);
    public Beacon? DeliveryBeacon => SalvageAvailable && Salvage.Towing
        ? Beacons.MinBy(beacon => Vector2.DistanceSquared(beacon.Position, Salvage.Position))
        : null;

    void UpdateSalvage(float dt)
    {
        if (!SalvageAvailable) return;
        if (!Salvage.Towing)
        {
            if (Vector2.DistanceSquared(Position, Salvage.Position) > SalvageCargo.HookRadius * SalvageCargo.HookRadius)
                return;

            Salvage.Towing = true;
            Events.Add(new("towHooked", Salvage.Position));
            if (!Salvage.Disturbed)
            {
                Salvage.Disturbed = true;
                SpawnScavengers();
            }
        }

        var pull = TowHook - Salvage.Position;
        float length = pull.Length();
        if (length >= SalvageCargo.BreakLength)
        {
            Salvage.Towing = false;
            Events.Add(new("towSnapped", Salvage.Position));
            return;
        }

        if (length > SalvageCargo.SlackLength)
        {
            float speed = Math.Min(Speed * 1.25f, (length - SalvageCargo.SlackLength) * 5);
            var next = Salvage.Position + pull / length * (speed * dt);
            Salvage.Position = World.Slide(Salvage.Position, next, 33);
        }

        if (DeliveryBeacon is not { } beacon ||
            Vector2.DistanceSquared(beacon.Position, Salvage.Position) > SalvageCargo.DeliveryRadius * SalvageCargo.DeliveryRadius)
            return;

        Salvage.Delivered = true;
        Salvage.Towing = false;
        bool salvager = Charter == Charter.Salvager;
        Xp += NextXp;
        Heal(salvager ? 45 : 25);
        Boost = 100;
        silver += salvager ? 5 : 3;
        Events.Add(new("towDelivered", Salvage.Position));
    }

    void SpawnScavengers()
    {
        var direction = OceanWorld.Unit(Position - World.SalvageWreck.Position, Vector2.UnitY);
        var side = new Vector2(-direction.Y, direction.X);
        var center = World.SalvageWreck.Position;
        var crab = center + direction * 285 + side * 230;
        var ray = center + direction * 265 - side * 270;
        if (World.IsWater(crab, 50)) AddEnemy(EnemyKind.Crab, crab);
        if (World.IsWater(ray, 50)) AddEnemy(EnemyKind.Ray, ray);
    }
}
