using System.Numerics;

namespace BoatsNBeasts.Core;

public sealed partial class Voyage
{
    public void Grapple(Enemy enemy)
    {
        if (enemy.Health <= 0) return;
        bool interrupt = enemy.Telegraph > 0 || enemy.Fuse > 0 || enemy.Dash > 0 || enemy.AttackClock < 1.1f;
        enemy.Stunned = interrupt ? 2.7f : 1.2f;
        enemy.AttackClock = Math.Max(enemy.AttackClock, 2);
        enemy.Telegraph = enemy.Fuse = enemy.Dash = 0;
        enemy.Position = World.Slide(enemy.Position, enemy.Position + OceanWorld.Unit(Position - enemy.Position) * (enemy.Marked ? 18 : 70), enemy.Radius);
        Events.Add(new("pull", Position, 2, enemy.Position));
        Hit(enemy, interrupt ? 19 : 8);
    }

    public Enemy? DropPatrol(EnemyKind kind, Vector2 at, float strength, bool marked)
    {
        if (!Spawn(kind)) return null;
        var e = Enemies[^1];
        if (World.IsWater(at, e.Radius)) e.Position = at;
        e.Marked = marked;
        e.Health = e.MaxHealth = (marked ? 120 : e.MaxHealth) * strength;
        if (marked) e.SpeedMultiplier *= .80f;
        return e;
    }

    public void HullHit(float damage) => DamagePlayer(damage);
    public void Patch(float health) => Heal(health);
}
