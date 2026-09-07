using Further.Core;
using System.Text.Json;
namespace Further;
public static class SourceTuning
{
    public static CombatTuning Load()
    {
        using var d=JsonDocument.Parse(File.ReadAllText(Art.Local("bonk.json")));
        AttackTuning Attack(string key,float damageScale=1,float cooldownScale=1)
        {
            var r=d.RootElement.GetProperty(key);
            return new(r.GetProperty("damage").GetSingle()*damageScale,r.GetProperty("endCooldown").GetSingle()*cooldownScale,r.GetProperty("burstTime").GetSingle(),r.GetProperty("projectiles").GetInt32(),r.GetProperty("knockback").GetSingle());
        }
        EnemyTuning Enemy(string key,float healthScale,float damageScale,float speedScale)
        {
            var r=d.RootElement.GetProperty(key);return new(r.GetProperty("hp").GetSingle()*healthScale,r.GetProperty("damage").GetSingle()*damageScale,r.GetProperty("speed").GetSingle()*speedScale);
        }
        // Explicit adaptation: fewer allies, slower enemies, readable projectile bursts.
        return new(Attack("WeaponSword",1.6f),Attack("WeaponRevolver",1.4f),Attack("WeaponLightningBolt",2),Attack("WeaponPoisonFlask",12,3),Enemy("Skeleton",1.1f,.45f,.48f),Enemy("SkeletonArmoredDusty",1.8f,1.1f,.4f),Attack("WeaponBow",1.6f),Attack("WeaponFrostWalker",.8f));
    }
}
