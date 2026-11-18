using System.Numerics;
namespace BoatsNBeasts.Core;

public readonly record struct WeaponMount(Vector3 Position, float Size);

public static class BoatRig
{
    public static readonly Vector3 Scale = new Vector3(1.22f, 1.15f, 1.30f) * 1.15f;

    public static WeaponKind Starter(BoatKind boat) => boat switch
    {
        BoatKind.Cutter => WeaponKind.Cannon,
        BoatKind.Trawler => WeaponKind.Undertow,
        _ => WeaponKind.Arcane
    };

    public static WeaponMount Mount(BoatKind boat, int[] ranks, WeaponKind weapon)
    {
        var starter = Starter(boat);
        if (weapon == starter)
            return new(weapon == WeaponKind.Cannon ? new(0, .26f, -.325f) : new(0, .25f, -.34f),
                weapon == WeaponKind.Arcane ? .95f : 1);

        int index = 0;
        for (int i = 0; i < (int)weapon; i++)
            if (i != (int)starter && ranks[i] > 0) index++;
        return new(new(index == 0 ? .115f : -.115f, .35f, .425f), .45f);
    }
}
