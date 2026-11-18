namespace BoatsNBeasts.Core;

public readonly record struct WeaponStats(float Damage, float ReloadSeconds, float Reach,
    int Projectiles = 1, int Targets = 1, int Ricochets = 0);

public sealed partial class Voyage
{
    public WeaponStats WeaponPerformance(WeaponKind kind, int rank)
    {
        float reload = 1 + ReloadRank * .12f;
        return kind switch
        {
            WeaponKind.Cannon => new(16, .85f / reload, 570 * Area, rank, Ricochets: rank == 5 ? 2 : 1),
            WeaponKind.Harpoon => new(17 + 4 * (rank - 1), 1.3f / reload, 570 * Area, Targets: rank == 5 ? 3 : 2),
            WeaponKind.Mine => new(38, (rank == 5 ? 1.65f : 2.4f) / reload, (109 + (rank - 1) * 30) * Area),
            WeaponKind.Coil => new(17 + 2 * (rank - 1), 1.55f / reload, 285 * Area, Targets: 2 + rank),
            WeaponKind.Undertow => new(9 + 2 * (rank - 1), .6f / reload, (154 + (rank - 1) * 30) * Area),
            _ => new(24, 1.19f / reload, 570 * Area, rank, rank == 5 ? 2 : 1)
        };
    }

    public string WeaponReadout(WeaponKind kind)
    {
        var stats = WeaponPerformance(kind, Weapons[(int)kind]);
        string area = kind is WeaponKind.Mine or WeaponKind.Undertow ? "radius" : "range";
        string damage = stats.Projectiles > 1 ? $"{stats.Damage:0} damage each" : $"{stats.Damage:0} damage";
        return $"{damage}  ·  {stats.Reach:0} m {area}  ·  {stats.ReloadSeconds:0.00}s reload";
    }

    string WeaponRefit(WeaponKind kind, int rank)
    {
        var before = WeaponPerformance(kind, Math.Max(1, rank));
        var after = WeaponPerformance(kind, rank + 1);
        string Change(float a, float b, string format = "0") =>
            rank > 0 && a != b ? $"{a.ToString(format)} → {b.ToString(format)}" : b.ToString(format);
        return kind switch
        {
            WeaponKind.Cannon => $"{Change(before.Projectiles, after.Projectiles)} {(after.Projectiles == 1 ? "cannonball" : "cannonballs")} · {after.Damage:0} damage each"
                + (after.Ricochets > before.Ricochets ? " · 2 ricochets each" : ""),
            WeaponKind.Harpoon => $"{Change(before.Damage, after.Damage)} damage · {Change(before.Targets, after.Targets)} targets"
                + (rank > 0 ? " · Stronger pull" : " · Pulls beasts"),
            WeaponKind.Mine => $"{Change(before.Reach, after.Reach)} m blast · {after.Damage:0} damage"
                + (after.ReloadSeconds < before.ReloadSeconds ? $" · {Change(before.ReloadSeconds, after.ReloadSeconds, "0.00")}s reload" : ""),
            WeaponKind.Coil => $"{Change(before.Damage, after.Damage)} damage · {Change(before.Targets, after.Targets)} targets",
            WeaponKind.Undertow => $"{Change(before.Damage, after.Damage)} damage · {Change(before.Reach, after.Reach)} m radius",
            _ => $"{Change(before.Projectiles, after.Projectiles)} homing {(after.Projectiles == 1 ? "orb" : "orbs")} · {after.Damage:0} damage each"
                + (after.Targets > before.Targets ? " · 2 targets each" : "")
        };
    }
}
