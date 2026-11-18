using System.Numerics;
namespace BoatsNBeasts.Core;

public sealed record WeaponCombo(string Name, string Description, WeaponKind First, WeaponKind Second)
{
    public static readonly WeaponCombo Stormshot = new("Stormshot", "Ricochets shock the next beasts they hit.",
        WeaponKind.Cannon, WeaponKind.Coil);
    public static readonly WeaponCombo Tripwire = new("Tripwire", "Harpoons drag beasts into armed mines.",
        WeaponKind.Harpoon, WeaponKind.Mine);
    public static readonly WeaponCombo Riptide = new("Riptide", "Orbs pierce an extra target after hitting whirlpool-marked beasts.",
        WeaponKind.Undertow, WeaponKind.Arcane);
    static readonly WeaponCombo[] All = [Stormshot, Tripwire, Riptide];

    public static WeaponCombo? ForUpgrade(int option) =>
        All.FirstOrDefault(combo => (int)combo.First == option || (int)combo.Second == option);

    public int Partner(int option) => (int)First == option ? (int)Second : (int)First;
}

public sealed partial class Voyage
{
    public WeaponCombo? ActiveCombo => IsFitted(WeaponCombo.Stormshot) ? WeaponCombo.Stormshot
        : IsFitted(WeaponCombo.Tripwire) ? WeaponCombo.Tripwire
        : IsFitted(WeaponCombo.Riptide) ? WeaponCombo.Riptide : null;

    bool IsFitted(WeaponCombo combo) => Weapons[(int)combo.First] > 0 && Weapons[(int)combo.Second] > 0;

    void RigHarpoon(Enemy enemy)
    {
        enemy.Pull = .4f;
        enemy.PullMine = IsFitted(WeaponCombo.Tripwire)
            ? Shots.Where(mine => mine.Kind == WeaponKind.Mine && mine.Life > 0 && mine.Age >= .5f &&
                Vector2.DistanceSquared(mine.Position, enemy.Position) < 248 * 248)
                .MinBy(mine => Vector2.DistanceSquared(mine.Position, enemy.Position))
            : null;

        HarpoonPulls++;
        Events.Add(new("pull", Position, Weapons[(int)WeaponKind.Harpoon], enemy.Position));
        if (enemy.PullMine is { } bait)
        {
            enemy.Pull = .63f;
            Events.Add(new("tripwire", enemy.Position, 0, bait.Position));
        }
    }

    Vector2 HarpoonForce(Enemy enemy, float dt)
    {
        enemy.Pull = Math.Max(0, enemy.Pull - dt);
        var mine = enemy.PullMine is { Life: > 0 } bait ? bait : null;
        if (enemy.Pull == 0) enemy.PullMine = null;
        var offset = (mine?.Position ?? Position) - enemy.Position;
        float reach = mine == null ? 110 : 18;
        if (offset.LengthSquared() <= reach * reach) return Vector2.Zero;

        float strength = 320 + (Weapons[(int)WeaponKind.Harpoon] - 1) * 160;
        if (mine != null) strength *= 1.25f;
        if (enemy.Kind == EnemyKind.Leviathan) strength *= .25f;
        return OceanWorld.Unit(offset) * strength;
    }

    void StrikeWithShot(Shot shot, Enemy enemy)
    {
        bool stormshot = shot.Kind == WeaponKind.Cannon && shot.Ricocheted &&
            !shot.ComboSpent && IsFitted(WeaponCombo.Stormshot);
        float discharge = stormshot ? 10 + Weapons[(int)WeaponKind.Coil] * 3 : 0;
        if (stormshot) shot.ComboSpent = true;

        if (shot.Kind == WeaponKind.Arcane && enemy.Drenched > 0 && !shot.ComboSpent)
        {
            shot.ComboSpent = true;
            shot.Pierce++;
            shot.Life = Math.Max(shot.Life, .8f);
            enemy.Drenched = 0;
            Events.Add(new("riptide", enemy.Position, enemy.Radius + 55));
        }

        Hit(enemy, shot.Damage + discharge);
        if (stormshot)
        {
            Events.Add(new("stormshot", enemy.Position, 105));
            foreach (var next in Enemies.Where(next => next.Health > 0 && !next.Emerging && next != enemy &&
                         !shot.Hit.Contains(next.Id) && Vector2.DistanceSquared(next.Position, enemy.Position) < 160 * 160)
                     .OrderBy(next => Vector2.DistanceSquared(next.Position, enemy.Position))
                     .Where(next => World.OpenShot(enemy.Position, next.Position)).Take(2))
            {
                if (next.Health <= 0) continue;
                Events.Add(new("arc", enemy.Position, 0, next.Position));
                Hit(next, discharge);
            }
        }
        if (shot.Kind == WeaponKind.Harpoon && enemy.Health > 0) RigHarpoon(enemy);
    }
}
