namespace Further.Core;
// Values are supplied by the private source package, never by a silent fallback.
public sealed record AttackTuning(float Damage,float Cooldown,float BurstTime,int Projectiles,float Knockback);
public sealed record EnemyTuning(float Health,float Damage,float Speed);
public sealed record CombatTuning(AttackTuning Sword,AttackTuning Gun,AttackTuning Spark,AttackTuning Bomb,EnemyTuning Sailor,EnemyTuning Brute,AttackTuning Harpoon,AttackTuning Frost);
